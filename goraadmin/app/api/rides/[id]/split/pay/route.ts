export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import Transaction from '@/models/Transaction'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

function normPhone(p: string): string {
  const digits = String(p || '').replace(/\D/g, '')
  return digits.slice(-10)
}

// POST /api/rides/{id}/split/pay — the split partner pays their own share
// from their own Gora wallet.
//
// This settles the driver's cut for that share immediately (rather than
// waiting for /complete), because the money genuinely arrived now — from the
// partner's wallet, not the ride's own rider. /complete later reduces what it
// bills against by `splitCollected` (fare portion only, never the tip) so the
// driver is never paid commission-adjusted earnings on the same rupee twice.
//
// Uses the ride's own commissionPercent (set at booking) rather than
// re-deriving a driver-subscription discount the way /complete does — a
// driver's mid-ride subscription change is a rare enough edge case that this
// is an acceptable simplification for a first version, not silently ignored.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    const myPhone = normPhone(payload.phone || '')
    const reqs: any[] = ride.splitRequests || []
    const idx = reqs.findIndex((s) => s.phone === myPhone && s.status === 'pending')
    if (idx === -1) return withCors({ error: 'No split request found for you on this ride' }, 404)

    const share = Math.round(reqs[idx].share || 0)
    if (share <= 0) return withCors({ error: 'Nothing to pay' }, 400)

    const user = await User.findById(payload.id)
    if (!user) return withCors({ error: 'User not found' }, 404)
    if ((user.walletBalance || 0) < share) {
      return withCors({ error: 'Insufficient wallet balance', balance: user.walletBalance || 0 }, 402)
    }

    user.walletBalance = (user.walletBalance || 0) - share
    await user.save()
    await WalletTransaction.create({
      userId: user._id, type: 'debit', amount: share, balanceAfter: user.walletBalance,
      note: `Split payment for ${ride.riderName || 'a'} ride`, source: 'ride', ref: String(ride._id),
    })

    ride.splitRequests[idx].status = 'paid'
    ride.splitRequests[idx].paidBy = user._id
    ride.splitRequests[idx].paidAt = new Date()
    ride.splitCollected = (ride.splitCollected || 0) + share

    const driver: any = ride.driverId ? await Driver.findById(ride.driverId) : null
    const commissionPercent = ride.commissionPercent != null ? ride.commissionPercent : 20
    const commission = Math.round((share * commissionPercent) / 100)
    ride.splitCommission = (ride.splitCommission || 0) + commission
    await ride.save()

    if (driver) {
      const driverShare = share - commission
      driver.walletBalance = (driver.walletBalance || 0) + driverShare
      driver.totalEarnings = (driver.totalEarnings || 0) + driverShare
      await driver.save()
      await Transaction.create({
        driverId: driver._id, rideId: ride._id, type: 'ride_earning',
        amount: driverShare, paymentMode: 'wallet',
        description: `Split-fare share from ${reqs[idx].name || 'a co-rider'} (admin took ₹${commission})`,
        balanceAfter: driver.walletBalance,
      })
    }

    return withCors({ success: true, balance: user.walletBalance, splitCollected: ride.splitCollected })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
