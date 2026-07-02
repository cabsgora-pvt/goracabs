export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import Transaction from '@/models/Transaction'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/driver/subscription/buy  body: { planId }
// Deducts the plan price from the driver wallet and activates the pass.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { planId } = await req.json()
    if (!planId) return withCors({ error: 'planId required' }, 400)

    await connectDB()
    const plan: any = await SubscriptionPlan.findById(planId).lean()
    if (!plan || !plan.isActive) return withCors({ error: 'Plan not available' }, 404)

    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    const price = Number(plan.price) || 0
    if ((driver.walletBalance || 0) < price) {
      return withCors({ error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: driver.walletBalance || 0 }, 402)
    }

    // If a plan is already active, extend from its expiry; else start now.
    const now = new Date()
    const base = driver.subscriptionActive && driver.subscriptionExpiresAt && new Date(driver.subscriptionExpiresAt) > now
      ? new Date(driver.subscriptionExpiresAt)
      : now
    const expiresAt = new Date(base.getTime() + (Number(plan.durationDays) || 0) * 24 * 60 * 60 * 1000)

    // Deduct wallet
    driver.walletBalance = (driver.walletBalance || 0) - price
    driver.subscriptionActive = true
    driver.subscriptionPlanId = plan._id
    driver.subscriptionPlanName = plan.name
    driver.subscriptionStartedAt = driver.subscriptionStartedAt && driver.subscriptionActive ? driver.subscriptionStartedAt : now
    driver.subscriptionExpiresAt = expiresAt
    driver.subscriptionCommissionPercent = Number(plan.commissionPercentWhileActive) || 0
    await driver.save()

    // Expire any previous active history rows, then log the new one
    await DriverSubscription.updateMany(
      { driverId: driver._id, status: 'active' },
      { $set: { status: 'expired' } }
    )
    const sub = await DriverSubscription.create({
      driverId: driver._id, planId: plan._id, planName: plan.name, price,
      durationDays: plan.durationDays, commissionPercentWhileActive: driver.subscriptionCommissionPercent,
      startedAt: now, expiresAt, status: 'active',
    })

    await Transaction.create({
      driverId: driver._id, type: 'subscription', amount: -price,
      description: `Subscription: ${plan.name} (${plan.durationDays} days)`,
      balanceAfter: driver.walletBalance,
    })

    return withCors({
      success: true,
      subscription: sub,
      walletBalance: driver.walletBalance,
      expiresAt,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
