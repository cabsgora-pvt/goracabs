export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import Transaction from '@/models/Transaction'
import { requireActiveRider } from '@/lib/auth'
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
// Order of steps (each atomic), so a double tap, two devices, or a /complete
// racing this request settle a share exactly once:
//   1. debit the partner's wallet ($gte guard);
//   2. ONE update claims the share (pending → paid, only while the ride is
//      accepted/arrived/ongoing with a driver) AND adds it to splitCollected /
//      splitCommission. /complete's own claim is conditioned on splitCollected,
//      so it either sees this share or retries — there is no window in which a
//      share is paid but not yet counted. If the claim fails, the debit is
//      given straight back;
//   3. credit the driver (share − commission), recorded on the share
//      (driverCredit / creditedDriverId) so a cancel can reverse exactly that.
// Commission follows /complete (lib/commission.ts), so a subscribed driver
// pays the plan's rate on split shares too.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const auth = await requireActiveRider(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)

    await connectDB()
    const user: any = await User.findById(auth.id).select('phone walletBalance').lean()
    if (!user) return withCors({ error: 'User not found' }, 404)
    const myPhone = normPhone(user.phone || auth.payload?.phone || '')

    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const mine = (ride.splitRequests || []).find((s: any) => s.phone === myPhone && s.status === 'pending')
    if (!mine) {
      const paid = (ride.splitRequests || []).find((s: any) => s.phone === myPhone && s.status === 'paid')
      if (paid) return withCors({ error: 'This share was already paid', code: 'alreadyPaid' }, 409)
      return withCors({ error: 'No split request found for you on this ride' }, 404)
    }
    if (!LIVE.includes(ride.status) || !ride.driverId) {
      return withCors({ error: 'Split shares can be paid only while the ride is on', code: 'rideNotLive' }, 400)
    }
    const share = Math.round(mine.share || 0)
    if (share <= 0) return withCors({ error: 'Nothing to pay' }, 400)

    const driver: any = await Driver.findById(ride.driverId).lean()
    const commissionPercent = await commissionPercentFor(driver, ride)
    const commission = Math.round((share * commissionPercent) / 100)
    const driverShare = share - commission

    // 1. Debit the partner.
    const debited: any = await User.findOneAndUpdate(
      { _id: user._id, walletBalance: { $gte: share } },
      { $inc: { walletBalance: -share } }, { new: true },
    ).select('walletBalance').lean()
    if (!debited) {
      const u: any = await User.findById(user._id).select('walletBalance').lean()
      return withCors({ error: 'Insufficient wallet balance', balance: u?.walletBalance || 0 }, 402)
    }

    // 2. Claim the share and count it, in one update.
    const now = new Date()
    const claimed: any = await Ride.findOneAndUpdate(
      {
        _id: ride._id, status: { $in: LIVE }, driverId: ride.driverId,
        splitRequests: { $elemMatch: { _id: mine._id, phone: myPhone, status: 'pending' } },
      },
      {
        $set: {
          'splitRequests.$.status': 'paid', 'splitRequests.$.paidBy': user._id, 'splitRequests.$.paidAt': now,
          'splitRequests.$.driverCredit': driverShare, 'splitRequests.$.creditedDriverId': ride.driverId,
        },
        $inc: { splitCollected: share, splitCommission: commission },
      },
      { new: true },
    ).select('splitCollected driverId').lean()
    if (!claimed) {
      // Lost the share to a parallel request, or the ride ended / changed driver.
      const back: any = await User.findByIdAndUpdate(user._id, { $inc: { walletBalance: share } }, { new: true }).select('walletBalance').lean()
      const now2: any = await Ride.findById(ride._id).select('status splitRequests').lean()
      const mineNow = (now2?.splitRequests || []).find((s: any) => String(s._id) === String(mine._id))
      if (mineNow?.status === 'paid') return withCors({ error: 'This share was already paid', code: 'alreadyPaid', balance: back?.walletBalance || 0 }, 409)
      return withCors({ error: 'Split shares can be paid only while the ride is on', code: 'rideNotLive', balance: back?.walletBalance || 0 }, 400)
    }
    await WalletTransaction.create({
      userId: user._id, type: 'debit', amount: share, balanceAfter: debited.walletBalance,
      note: `Split payment for ${ride.riderName || 'a'} ride`, source: 'ride', ref: String(ride._id),
    })

    // 3. The driver's cut.
    if (driverShare > 0) {
      const d: any = await Driver.findByIdAndUpdate(ride.driverId,
        { $inc: { walletBalance: driverShare, totalEarnings: driverShare } }, { new: true }).lean()
      await Transaction.create({
        driverId: ride.driverId, rideId: ride._id, type: 'ride_earning',
        amount: driverShare, paymentMode: 'wallet',
        description: `Split-fare share from ${mine.name || 'a co-rider'} (admin took ₹${commission})`,
        balanceAfter: d?.walletBalance,
      })
    }

    return withCors({ success: true, balance: debited.walletBalance, splitCollected: claimed.splitCollected || 0 })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
