export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature } from '@/lib/razorpay'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

export async function OPTIONS() { return corsOptions() }

// POST /api/payment/razorpay/verify
// body: { orderId, paymentId, signature, purpose, amount, rideId? }
// Verifies signature; for purpose 'wallet' credits the wallet (idempotent).
export async function POST(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { orderId, paymentId, signature, purpose = 'wallet', amount, rideId = '' } = await req.json()
    if (!orderId || !paymentId || !signature) return withCors({ error: 'Missing payment fields' }, 400)

    const valid = await verifyRazorpaySignature(orderId, paymentId, signature)
    if (!valid) return withCors({ error: 'Payment verification failed' }, 400)

    await connectDB()

    if (purpose === 'wallet') {
      const amt = Math.round(Number(amount) || 0)
      if (amt <= 0) return withCors({ error: 'Invalid amount' }, 400)

      // Idempotency: if this paymentId was already credited, return current balance
      const existing = await WalletTransaction.findOne({ ref: paymentId })
      const user = await User.findById(payload.id)
      if (!user) return withCors({ error: 'User not found' }, 404)
      if (existing) return withCors({ success: true, balance: user.walletBalance || 0 })

      user.walletBalance = (user.walletBalance || 0) + amt
      await user.save()
      await WalletTransaction.create({
        userId: user._id, type: 'credit', amount: amt, balanceAfter: user.walletBalance,
        note: 'Money added via Razorpay', source: 'recharge', ref: paymentId,
      })
      return withCors({ success: true, balance: user.walletBalance })
    }

    // purpose 'ride' (or others): payment verified — booking flow will attach paymentId
    return withCors({ success: true, paymentId, rideId })
  } catch {
    return withCors({ error: 'Verification failed' }, 500)
  }
}
