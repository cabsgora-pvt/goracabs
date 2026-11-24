export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import User from '@/models/User'
import Ride from '@/models/Ride'
import WalletTransaction from '@/models/WalletTransaction'
// The same rule /rides/{id}/complete settles with (fare + waiting − split
// shares + tip − server coupon − prepaid).
import { riderAmountDue } from '@/lib/settlement'

export async function OPTIONS() { return corsOptions() }

const MAX_PAY = 100000

// One atomic debit: the balance check and the deduction are a single update,
// so two parallel requests can never both spend the same rupees. With a claim
// key the same update also records it on the user, so a ride is paid at most
// once even when two requests race past the "already paid" checks.
async function debit(userId: string, amt: number, claimKey?: string) {
  const filter: any = { _id: userId, walletBalance: { $gte: amt } }
  const update: any = { $inc: { walletBalance: -amt } }
  if (claimKey) {
    filter.walletRechargeRefs = { $ne: claimKey }
    update.$push = { walletRechargeRefs: claimKey }
  }
  return User.findOneAndUpdate(filter, update, { new: true }).select('walletBalance').lean() as any
}

async function balanceOf(userId: string): Promise<number> {
  const u: any = await User.findById(userId).select('walletBalance').lean()
  return u?.walletBalance || 0
}

// POST /api/wallet/pay  body: { amount, note?, rideId? }
//   rideId given  → pay that ride from the wallet. Normally /rides/{id}/complete
//                   has already debited it on the server and this returns
//                   { success, alreadyPaid } without touching the balance
//                   (installed apps still call it after completion). Only an
//                   unpaid ride is debited here, and always the amount the
//                   SERVER computes — the client's amount is ignored.
//   no rideId     → outstation prepayment before the ride exists (lib/prepay.ts
//                   links it to the booking): debits `amount`, ref ''.
export async function POST(req: NextRequest) {
  try {
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const body = await req.json().catch(() => ({}))
    const note = typeof body.note === 'string' && body.note.trim() ? body.note.trim().slice(0, 120) : 'Ride payment'
    const rideId = body.rideId ? String(body.rideId) : ''

    await connectDB()

    if (rideId) {
      if (!mongoose.isValidObjectId(rideId)) return withCors({ error: 'Invalid ride' }, 400)
      const ride: any = await Ride.findById(rideId).lean()
      if (!ride) return withCors({ error: 'Ride not found' }, 404)
      if (String(ride.riderId || '') !== String(payload.id)) return withCors({ error: 'Not your ride' }, 403)

      const claimKey = `ride:${rideId}`
      const already =
        ride.paymentStatus === 'paid' ||
        (ride.riderWalletDebit || 0) > 0 ||
        !!(await WalletTransaction.exists({ userId: payload.id, type: 'debit', source: 'ride', ref: rideId })) ||
        !!(await User.exists({ _id: payload.id, walletRechargeRefs: claimKey }))
      if (already) return withCors({ success: true, alreadyPaid: true, balance: await balanceOf(payload.id) })

      if (ride.paymentMode !== 'wallet') return withCors({ error: 'This ride is not paid by wallet' }, 400)
      const amt = riderAmountDue(ride)
      if (amt <= 0) return withCors({ success: true, alreadyPaid: true, balance: await balanceOf(payload.id) })

      const updated = await debit(payload.id, amt, claimKey)
      if (!updated) {
        // Either the balance is short, or a parallel request claimed this ride.
        const u: any = await User.findById(payload.id).select('walletBalance walletRechargeRefs').lean()
        if (!u) return withCors({ error: 'User not found' }, 404)
        if ((u.walletRechargeRefs || []).includes(claimKey)) return withCors({ success: true, alreadyPaid: true, balance: u.walletBalance || 0 })
        return withCors({ error: 'Insufficient wallet balance', balance: u.walletBalance || 0, amountDue: amt }, 402)
      }
      await WalletTransaction.create({
        userId: payload.id, type: 'debit', amount: amt, balanceAfter: updated.walletBalance,
        note, source: 'ride', ref: rideId,
      })
      return withCors({ success: true, amount: amt, balance: updated.walletBalance })
    }

    // ── Outstation prepayment (no ride yet) ──
    const amt = Math.round(Number(body.amount) || 0)
    if (amt < 1 || amt > MAX_PAY) return withCors({ error: 'Invalid amount' }, 400)
    const updated = await debit(payload.id, amt)
    if (!updated) {
      const exists = await User.exists({ _id: payload.id })
      if (!exists) return withCors({ error: 'User not found' }, 404)
      return withCors({ error: 'Insufficient wallet balance', balance: await balanceOf(payload.id) }, 402)
    }
    await WalletTransaction.create({
      userId: payload.id, type: 'debit', amount: amt, balanceAfter: updated.walletBalance,
      note, source: 'ride', ref: '',
    })
    return withCors({ success: true, balance: updated.walletBalance })
  } catch {
    return withCors({ error: 'Payment failed' }, 500)
  }
}
