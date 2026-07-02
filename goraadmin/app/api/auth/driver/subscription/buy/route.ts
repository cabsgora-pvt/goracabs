export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import Transaction from '@/models/Transaction'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature } from '@/lib/razorpay'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/driver/subscription/buy
// body: { planId, orderId?, paymentId?, signature? }
//   - Razorpay path: orderId+paymentId+signature present → verify → activate (no wallet change)
//   - Wallet path (gateway off): no payment fields → deduct plan price from wallet
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { planId, orderId, paymentId, signature } = await req.json()
    if (!planId) return withCors({ error: 'planId required' }, 400)

    await connectDB()
    const plan: any = await SubscriptionPlan.findById(planId).lean()
    if (!plan || !plan.isActive) return withCors({ error: 'Plan not available' }, 404)

    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    const price = Number(plan.price) || 0
    const paidViaGateway = !!(orderId && paymentId && signature)

    if (paidViaGateway) {
      // Verify the Razorpay payment before activating
      const valid = await verifyRazorpaySignature(orderId, paymentId, signature)
      if (!valid) return withCors({ error: 'Payment verification failed' }, 400)
    } else {
      // Wallet fallback (gateway not configured) — deduct from driver wallet
      if ((driver.walletBalance || 0) < price) {
        return withCors({ error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: driver.walletBalance || 0 }, 402)
      }
      driver.walletBalance = (driver.walletBalance || 0) - price
    }

    // Activate / extend the pass
    const now = new Date()
    const base = driver.subscriptionActive && driver.subscriptionExpiresAt && new Date(driver.subscriptionExpiresAt) > now
      ? new Date(driver.subscriptionExpiresAt)
      : now
    const expiresAt = new Date(base.getTime() + (Number(plan.durationDays) || 0) * 24 * 60 * 60 * 1000)

    driver.subscriptionActive = true
    driver.subscriptionPlanId = plan._id
    driver.subscriptionPlanName = plan.name
    if (!driver.subscriptionStartedAt || base === now) driver.subscriptionStartedAt = now
    driver.subscriptionExpiresAt = expiresAt
    driver.subscriptionCommissionPercent = Number(plan.commissionPercentWhileActive) || 0
    await driver.save()

    await DriverSubscription.updateMany(
      { driverId: driver._id, status: 'active' },
      { $set: { status: 'expired' } }
    )
    const sub = await DriverSubscription.create({
      driverId: driver._id, planId: plan._id, planName: plan.name, price,
      durationDays: plan.durationDays, commissionPercentWhileActive: driver.subscriptionCommissionPercent,
      startedAt: now, expiresAt, status: 'active',
    })

    // Only record a wallet transaction when paid from wallet (gateway payments don't touch the wallet)
    if (!paidViaGateway) {
      await Transaction.create({
        driverId: driver._id, type: 'subscription', amount: -price,
        description: `Subscription: ${plan.name} (${plan.durationDays} days)`,
        balanceAfter: driver.walletBalance,
      })
    }

    return withCors({
      success: true,
      subscription: sub,
      walletBalance: driver.walletBalance,
      expiresAt,
      paidVia: paidViaGateway ? 'razorpay' : 'wallet',
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
