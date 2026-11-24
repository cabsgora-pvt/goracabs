export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import Transaction from '@/models/Transaction'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { commissionPercentFor } from '@/lib/commission'

export async function OPTIONS() { return corsOptions() }

function normPhone(p: string): string {
  const digits = String(p || '').replace(/\D/g, '')
  return digits.slice(-10)
}

const LIVE = ['accepted', 'arrived', 'ongoing']

// POST /api/rides/{id}/split/pay — the split partner pays their own share
// from their own Gora wallet.
//
// This settles the driver's cut for that share immediately (rather than
// waiting for /complete), because the money genuinely arrived now. /complete
// later reduces what it bills by `splitCollected` (fare portion only, never
// the tip), so the driver is never paid on the same rupee twice.
//
// Every step is atomic, so a double tap or two devices pay a share once:
//   1. claim the share: splitRequests.$.status pending → paid, only while the
//      ride is accepted/arrived/ongoing with a driver;
//   2. debit the partner's wallet with a $gte guard (claim undone if short);
//   3. $inc the ride's splitCollected/splitCommission and the driver's wallet.
// Commission follows /complete (lib/commission.ts), so a subscribed driver
// pays the plan's rate on split shares too.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)

    await connectDB()
    const user: any = await User.findById(payload.id).select('phone walletBalance').lean()
    if (!user) return withCors({ error: 'User not found' }, 404)
    const myPhone = normPhone(user.phone || payload.phone || '')

    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const mine = (ride.splitRequests || []).find((s: any) => s.phone === myPhone && s.status === 'pending')
    if (!mine) return withCors({ error: 'No split request found for you on this ride' }, 404)
    if (!LIVE.includes(ride.status) || !ride.driverId) {
      return withCors({ error: 'Split shares can be paid only while the ride is on', code: 'rideNotLive' }, 400)
    }
    const share = Math.round(mine.share || 0)
    if (share <= 0) return withCors({ error: 'Nothing to pay' }, 400)

    // 1. Claim the share.
    const now = new Date()
    const claimed: any = await Ride.findOneAndUpdate(
      {
        _id: ride._id, status: { $in: LIVE }, driverId: { $ne: null },
        splitRequests: { $elemMatch: { _id: mine._id, phone: myPhone, status: 'pending' } },
      },
      { $set: { 'splitRequests.$.status': 'paid', 'splitRequests.$.paidBy': user._id, 'splitRequests.$.paidAt': now } },
      { new: true },
    ).lean()
    if (!claimed) return withCors({ error: 'This share was already paid', code: 'alreadyPaid' }, 409)

    // 2. Debit the partner.
    const debited: any = await User.findOneAndUpdate(
      { _id: user._id, walletBalance: { $gte: share } },
      { $inc: { walletBalance: -share } }, { new: true },
    ).select('walletBalance').lean()
    if (!debited) {
      await Ride.updateOne(
        { _id: ride._id, splitRequests: { $elemMatch: { _id: mine._id, status: 'paid', paidBy: user._id } } },
        { $set: { 'splitRequests.$.status': 'pending' }, $unset: { 'splitRequests.$.paidBy': 1, 'splitRequests.$.paidAt': 1 } },
      )
      const u: any = await User.findById(user._id).select('walletBalance').lean()
      return withCors({ error: 'Insufficient wallet balance', balance: u?.walletBalance || 0 }, 402)
    }
    await WalletTransaction.create({
      userId: user._id, type: 'debit', amount: share, balanceAfter: debited.walletBalance,
      note: `Split payment for ${ride.riderName || 'a'} ride`, source: 'ride', ref: String(ride._id),
    })

    // 3. Ride totals and the driver's cut.
    const driver: any = await Driver.findById(claimed.driverId).lean()
    const commissionPercent = await commissionPercentFor(driver, claimed)
    const commission = Math.round((share * commissionPercent) / 100)
    const after: any = await Ride.findByIdAndUpdate(ride._id,
      { $inc: { splitCollected: share, splitCommission: commission } }, { new: true }).select('splitCollected').lean()

    if (driver) {
      const driverShare = share - commission
      const d: any = await Driver.findByIdAndUpdate(driver._id,
        { $inc: { walletBalance: driverShare, totalEarnings: driverShare } }, { new: true }).lean()
      await Transaction.create({
        driverId: driver._id, rideId: ride._id, type: 'ride_earning',
        amount: driverShare, paymentMode: 'wallet',
        description: `Split-fare share from ${mine.name || 'a co-rider'} (admin took ₹${commission})`,
        balanceAfter: d?.walletBalance,
      })
    }

    return withCors({ success: true, balance: debited.walletBalance, splitCollected: after?.splitCollected || 0 })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
