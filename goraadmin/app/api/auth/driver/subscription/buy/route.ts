export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import Transaction from '@/models/Transaction'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature, fetchRazorpayOrder } from '@/lib/razorpay'
import { franchiseShareFor } from '@/lib/commission'

export async function OPTIONS() { return corsOptions() }

const DAY = 24 * 60 * 60 * 1000
// A second wallet purchase of the same plan this soon after the last one is
// treated as a double tap of the same purchase, not a new one.
const WALLET_DEDUPE_MS = 30 * 1000

// POST /api/auth/driver/subscription/buy
// body: { planId, orderId?, paymentId?, signature? }
//   - Razorpay path: orderId+paymentId+signature → verify the signature, then
//     read the order back from Razorpay: it must be OUR subscription order for
//     this driver and this plan (notes.purpose 'driver_subscription',
//     notes.driverId, notes.planId — stamped by /subscription/order) and
//     amount_paid must cover the plan price. Each payment id activates once.
//   - Wallet path (gateway off): no payment fields → deduct plan price from wallet
//
// The pass is extended with an optimistic guard on subscriptionExpiresAt, in the
// same atomic update as the wallet debit / payment claim, so two parallel
// requests can never both extend it.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { planId, orderId, paymentId, signature } = await req.json().catch(() => ({}))
    if (!planId || !mongoose.isValidObjectId(String(planId))) return withCors({ error: 'planId required' }, 400)

    await connectDB()
    const plan: any = await SubscriptionPlan.findById(planId).lean()
    if (!plan || !plan.isActive) return withCors({ error: 'Plan not available' }, 404)

    const exists = await Driver.exists({ _id: payload.id })
    if (!exists) return withCors({ error: 'Driver not found' }, 404)

    const price = Math.max(0, Number(plan.price) || 0)
    const durationMs = (Number(plan.durationDays) || 0) * DAY
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

    let updated: any = null
    let now = new Date(), expiresAt = now, claimKey = ''
    // Gateway: retry on a lost race (the key is the payment id, so a retry can
    // never apply it twice). Wallet: one attempt only — a retry would read the
    // expiry a racing duplicate just set and build a NEW key from it; instead
    // the duplicate finds its key already claimed below and reports alreadyApplied.
    const attempts = paidViaGateway ? 5 : 1
    for (let attempt = 0; attempt < attempts && !updated; attempt++) {
      const d: any = await Driver.findById(payload.id).select('subscriptionExpiresAt walletBalance walletRechargeRefs').lean()
      if (!d) return withCors({ error: 'Driver not found' }, 404)
      now = new Date()
      const cur: Date | null = d.subscriptionExpiresAt ? new Date(d.subscriptionExpiresAt) : null
      const extending = !!cur && cur > now
      const base = extending && cur ? cur : now
      expiresAt = new Date(base.getTime() + durationMs)
      // Gateway: the payment id. Wallet: the plan + the expiry this request
      // extends — a racing duplicate reads the same expiry, so the same key.
      claimKey = paidViaGateway ? `sub:${paymentId}` : `subw:${plan._id}:${cur ? cur.getTime() : 0}`
      if ((d.walletRechargeRefs || []).includes(claimKey)) break

      const filter: any = { _id: payload.id, subscriptionExpiresAt: d.subscriptionExpiresAt ?? null, walletRechargeRefs: { $ne: claimKey } }
      const set: any = {
        subscriptionActive: true,
        subscriptionPlanId: plan._id,
        subscriptionPlanName: plan.name,
        subscriptionExpiresAt: expiresAt,
        subscriptionCommissionPercent: Number(plan.commissionPercentWhileActive) || 0,
      }
      if (!extending) set.subscriptionStartedAt = now
      const update: any = { $set: set, $push: { walletRechargeRefs: claimKey } }
      if (!paidViaGateway) {
        if ((d.walletBalance || 0) < price) {
          return withCors({ error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: d.walletBalance || 0 }, 402)
        }
        filter.walletBalance = { $gte: price }
        update.$inc = { walletBalance: -price }
      }
      updated = await Driver.findOneAndUpdate(filter, update, { new: true })
        .select('walletBalance zoneId subscriptionCommissionPercent').lean()
    }

    if (!updated) {
      const d: any = await Driver.findById(payload.id).select('walletBalance walletRechargeRefs subscriptionExpiresAt').lean()
      if ((d?.walletRechargeRefs || []).includes(claimKey)) {
        // Replay of an already-used payment / duplicate submit: nothing more to do.
        const last = await DriverSubscription.findOne({ driverId: payload.id }).sort({ createdAt: -1 }).lean()
        return withCors({ success: true, alreadyApplied: true, subscription: last, walletBalance: d?.walletBalance || 0, expiresAt: d?.subscriptionExpiresAt, paidVia: paidViaGateway ? 'razorpay' : 'wallet' })
      }
      if (!paidViaGateway && (d?.walletBalance || 0) < price) {
        return withCors({ error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: d?.walletBalance || 0 }, 402)
      }
      return withCors({ error: 'Busy, please try again' }, 409)
    }

    await DriverSubscription.updateMany(
      { driverId: payload.id, status: 'active' },
      { $set: { status: 'expired' } }
    )
    // Franchise mode: a subscribed driver pays no ride commission, so the zone
    // admin's share comes from the subscription price instead (lib/commission).
    let franchiseShare: any
    try { franchiseShare = await franchiseShareFor(updated.zoneId, price) } catch (e) { console.error('[subscription] franchise share failed', e) }
    const sub = await DriverSubscription.create({
      driverId: payload.id, planId: plan._id, planName: plan.name, price,
      durationDays: plan.durationDays, commissionPercentWhileActive: updated.subscriptionCommissionPercent,
      startedAt: now, expiresAt, status: 'active',
      zoneId: updated.zoneId || null, paidVia: paidViaGateway ? 'razorpay' : 'wallet', franchiseShare,
    })

    // Only record a wallet transaction when paid from wallet (gateway payments don't touch the wallet)
    if (!paidViaGateway) {
      await Transaction.create({
        driverId: payload.id, type: 'subscription', amount: -price,
        description: `Subscription: ${plan.name} (${plan.durationDays} days)`,
        balanceAfter: updated.walletBalance,
      })
    }

    return withCors({
      success: true,
      subscription: sub,
      walletBalance: updated.walletBalance,
      expiresAt,
      paidVia: paidViaGateway ? 'razorpay' : 'wallet',
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
