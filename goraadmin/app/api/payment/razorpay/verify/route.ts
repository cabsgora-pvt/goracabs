export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature, fetchRazorpayOrder } from '@/lib/razorpay'
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

    // No 'amount' here: what to credit comes from Razorpay, never from the app.
    const { orderId, paymentId, signature, purpose = 'wallet', rideId = '' } = await req.json()
    if (!orderId || !paymentId || !signature) return withCors({ error: 'Missing payment fields' }, 400)

    const valid = await verifyRazorpaySignature(orderId, paymentId, signature)
    if (!valid) return withCors({ error: 'Payment verification failed' }, 400)

    await connectDB()

    if (purpose === 'wallet') {
      // Credit what Razorpay says was paid on an order created for THIS user.
      // The amount used to come from the request body, so paying ₹1 and
      // sending amount: 10000 added ₹10,000.
      const res = await fetchRazorpayOrder(String(orderId))
      if (!res.ok || !res.order) return withCors({ error: 'Could not confirm the payment with Razorpay' }, 502)
      const o = res.order
      if (String(o.notes?.userId || '') !== String(payload.id) || String(o.notes?.purpose || 'wallet') !== 'wallet') {
        return withCors({ error: 'This payment is not a wallet top-up for your account' }, 400)
      }
      const amt = Math.round(Number(o.amount_paid) || 0) / 100
      if (amt <= 0) return withCors({ error: 'Payment not completed yet' }, 400)

      // A payment credited before this rule has a ledger row: never again.
      if (await WalletTransaction.exists({ ref: paymentId, source: 'recharge' })) {
        const u: any = await User.findById(payload.id).select('walletBalance').lean()
        return withCors({ success: true, alreadyCredited: true, balance: u?.walletBalance || 0 })
      }
      // Claim and credit in one atomic update on the user: a retried or doubled
      // verify finds the payment id already there and adds nothing.
      const updated: any = await User.findOneAndUpdate(
        { _id: payload.id, walletRechargeRefs: { $ne: paymentId } },
        { $inc: { walletBalance: amt }, $push: { walletRechargeRefs: paymentId } },
        { new: true },
      ).select('walletBalance').lean()
      if (!updated) {
        const u: any = await User.findById(payload.id).select('walletBalance').lean()
        if (!u) return withCors({ error: 'User not found' }, 404)
        return withCors({ success: true, alreadyCredited: true, balance: u.walletBalance || 0 })
      }
      await WalletTransaction.create({
        userId: updated._id, type: 'credit', amount: amt, balanceAfter: updated.walletBalance,
        note: 'Money added via Razorpay', source: 'recharge', ref: paymentId,
      })
      return withCors({ success: true, amount: amt, balance: updated?.walletBalance || 0 })
    }

    // purpose 'ride' (or others): payment verified — booking flow will attach paymentId
    return withCors({ success: true, paymentId, rideId })
  } catch {
    return withCors({ error: 'Verification failed' }, 500)
  }
}
