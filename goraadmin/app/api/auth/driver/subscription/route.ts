export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/subscription
// → { current, history, plans, walletBalance }  (driver app membership screen)
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Auto-expire a lapsed subscription
    const now = Date.now()
    if (driver.subscriptionActive && driver.subscriptionExpiresAt && new Date(driver.subscriptionExpiresAt).getTime() < now) {
      driver.subscriptionActive = false
      await driver.save()
      await DriverSubscription.updateMany(
        { driverId: driver._id, status: 'active' },
        { $set: { status: 'expired' } }
      )
    }

    const current = driver.subscriptionActive ? {
      active: true,
      planName: driver.subscriptionPlanName,
      planId: driver.subscriptionPlanId,
      startedAt: driver.subscriptionStartedAt,
      expiresAt: driver.subscriptionExpiresAt,
      commissionPercent: driver.subscriptionCommissionPercent,
    } : { active: false }

    const history = await DriverSubscription.find({ driverId: driver._id }).sort({ createdAt: -1 }).limit(20).lean()
    const plans = await SubscriptionPlan.find({ isActive: true }).sort({ sortOrder: 1, price: 1 }).lean()

    return withCors({ current, history, plans, walletBalance: driver.walletBalance || 0 })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
