export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import { requireActiveDriver } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature, fetchRazorpayOrder } from '@/lib/razorpay'
import { applyDriverSubscription } from '@/lib/payment-credit'

export async function OPTIONS() { return corsOptions() }

// A second wallet purchase of the same plan this soon after the last one is
// treated as a double tap of the same purchase, not a new one.
const WALLET_DEDUPE_MS = 30 * 1000

// POST /api/auth/driver/subscription/buy
// body: { planId, orderId?, paymentId?, signature? }
//   - Razorpay path: orderId+paymentId+signature → verify the signature, then
//     read the order back from Razorpay: it must be OUR subscription order for
//     this driver and this plan (notes.purpose 'driver_subscription',
//     notes.driverId, notes.planId — stamped by /subscription/order) and
//     amount_paid must cover the plan price. Each payment id activates once —
//     the Razorpay webhook applies the same payment with the same claim
//     ('sub:<paymentId>'), so whichever arrives second reports alreadyApplied.
//   - Wallet path (gateway off): no payment fields → deduct plan price from wallet
//
// Activation itself is lib/payment-credit applyDriverSubscription.
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveDriver(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const payload = { id: auth.id }

    const { planId, orderId, paymentId, signature } = await req.json().catch(() => ({}))
    if (!planId || !mongoose.isValidObjectId(String(planId))) return withCors({ error: 'planId required' }, 400)

    await connectDB()
    const plan: any = await SubscriptionPlan.findById(planId).lean()
    if (!plan || !plan.isActive) return withCors({ error: 'Plan not available' }, 404)

    const exists = await Driver.exists({ _id: payload.id })
    if (!exists) return withCors({ error: 'Driver not found' }, 404)

    const price = Math.max(0, Number(plan.price) || 0)
    const paidViaGateway = !!(orderId || paymentId || signature)

    if (paidViaGateway) {
      if (!orderId || !paymentId || !signature) return withCors({ error: 'Missing payment fields' }, 400)
      const valid = await verifyRazorpaySignature(String(orderId), String(paymentId), String(signature))
      if (!valid) return withCors({ error: 'Payment verification failed' }, 400)
      const res = await fetchRazorpayOrder(String(orderId))
      if (!res.ok || !res.order) {
        return withCors({ error: 'Could not confirm the payment with Razorpay. If money was taken, contact support.' }, 502)
      }
      const o = res.order
      const purpose = String(o.notes?.purpose || '')
      // 'subscription' = orders made by /subscription/order before the purpose
      // was renamed; driverId + planId are only ever stamped by that route.
      if (!['driver_subscription', 'subscription'].includes(purpose) ||
          String(o.notes?.driverId || '') !== String(payload.id) ||
          String(o.notes?.planId || '') !== String(plan._id)) {
        return withCors({ error: 'This payment is not for this plan on your account' }, 400)
      }
      if ((Number(o.amount_paid) || 0) < Math.round(price * 100)) {
        return withCors({ error: 'Payment amount does not cover this plan' }, 400)
      }
    } else {
      // Double tap: the same plan was just bought from the wallet.
      const recent: any = await DriverSubscription.findOne({
        driverId: payload.id, planId: plan._id, paidVia: 'wallet',
        createdAt: { $gte: new Date(Date.now() - WALLET_DEDUPE_MS) },
      }).sort({ createdAt: -1 }).lean()
      if (recent) {
        const d: any = await Driver.findById(payload.id).select('walletBalance').lean()
        return withCors({ success: true, alreadyApplied: true, subscription: recent, walletBalance: d?.walletBalance || 0, expiresAt: recent.expiresAt, paidVia: 'wallet' })
      }
    }

    const out = await applyDriverSubscription(String(payload.id), plan, paidViaGateway ? String(paymentId) : undefined)
    return withCors(out.body, out.status)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
