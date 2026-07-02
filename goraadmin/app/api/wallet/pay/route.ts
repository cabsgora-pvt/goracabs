export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

export async function OPTIONS() { return corsOptions() }

// POST /api/wallet/pay  body: { amount, note?, rideId? }
// Deducts fare from wallet balance for a ride payment. Fails if low balance.
export async function POST(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { amount, note = 'Ride payment', rideId = '' } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (amt <= 0) return withCors({ error: 'Invalid amount' }, 400)

    await connectDB()
    const user = await User.findById(payload.id)
    if (!user) return withCors({ error: 'User not found' }, 404)

    if ((user.walletBalance || 0) < amt) {
      return withCors({ error: 'Insufficient wallet balance', balance: user.walletBalance || 0 }, 402)
    }

    user.walletBalance = (user.walletBalance || 0) - amt
    await user.save()
    await WalletTransaction.create({
      userId: user._id, type: 'debit', amount: amt, balanceAfter: user.walletBalance,
      note, source: 'ride', ref: rideId ? String(rideId) : '',
    })
    return withCors({ success: true, balance: user.walletBalance })
  } catch {
    return withCors({ error: 'Payment failed' }, 500)
  }
}
