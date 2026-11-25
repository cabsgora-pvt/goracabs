export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireActiveRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import { payRideFromWallet } from '@/lib/settlement'

export async function OPTIONS() { return corsOptions() }

const MAX_PAY = 100000

async function balanceOf(userId: string): Promise<number> {
  const u: any = await User.findById(userId).select('walletBalance').lean()
  return u?.walletBalance || 0
}

// POST /api/wallet/pay  body: { amount, note?, rideId? }
//   rideId given  → pay that ride from the wallet (lib/settlement
//                   payRideFromWallet). Allowed only once the ride is
//                   COMPLETED, unpaid and a wallet ride: the amount is the
//                   SERVER's amountDue (the client's amount is ignored).
//                   Normally /rides/{id}/complete has already debited it and
//                   this returns { success, alreadyPaid } without touching the
//                   balance (installed apps still call it after completion).
//                   A ride not ended yet → 409 { code: 'notPayableYet' }: paying
//                   the booked fare mid-trip used to skip every later extra.
//   no rideId     → outstation prepayment before the ride exists (lib/prepay.ts
//                   links it to the booking): debits `amount`, ref ''. One that
//                   no booking links within 15 minutes is refunded by the
//                   orphan sweep (POST /api/cron/payments).
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveRider(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const userId = auth.id

    const body = await req.json().catch(() => ({}))
    const note = typeof body.note === 'string' && body.note.trim() ? body.note.trim().slice(0, 120) : 'Ride payment'
    const rideId = body.rideId ? String(body.rideId) : ''

    await connectDB()

    if (rideId) {
      if (!mongoose.isValidObjectId(rideId)) return withCors({ error: 'Invalid ride' }, 400)
      const out = await payRideFromWallet(rideId, userId, note)
      return withCors(out.body, out.status)
    }

    // ── Outstation prepayment (no ride yet) ──
    const amt = Math.round(Number(body.amount) || 0)
    if (amt < 1 || amt > MAX_PAY) return withCors({ error: 'Invalid amount' }, 400)
    const updated: any = await User.findOneAndUpdate(
      { _id: userId, walletBalance: { $gte: amt } },
      { $inc: { walletBalance: -amt } }, { new: true },
    ).select('walletBalance').lean()
    if (!updated) {
      const exists = await User.exists({ _id: userId })
      if (!exists) return withCors({ error: 'User not found' }, 404)
      return withCors({ error: 'Insufficient wallet balance', balance: await balanceOf(userId) }, 402)
    }
    await WalletTransaction.create({
      userId, type: 'debit', amount: amt, balanceAfter: updated.walletBalance,
      note, source: 'ride', ref: '',
    })
    return withCors({ success: true, balance: updated.walletBalance })
  } catch {
    return withCors({ error: 'Payment failed' }, 500)
  }
}
