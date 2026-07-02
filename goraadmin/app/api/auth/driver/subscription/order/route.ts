export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { createRazorpayOrder } from '@/lib/razorpay'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/driver/subscription/order  body: { planId }
// Creates a Razorpay order for the plan price so the driver can pay for a pass.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) {
      console.log('[SubOrder] Unauthorized — no/invalid driver token')
      return withCors({ error: 'Unauthorized' }, 401)
    }

    const { planId } = await req.json()
    if (!planId) return withCors({ error: 'planId required' }, 400)
    console.log(`[SubOrder] driver=${payload.id} planId=${planId}`)

    await connectDB()
    const plan: any = await SubscriptionPlan.findById(planId).lean()
    if (!plan || !plan.isActive) return withCors({ error: 'Plan not available' }, 404)

    const price = Number(plan.price) || 0
    if (price <= 0) return withCors({ error: 'Invalid plan price' }, 400)

    const receipt = `sub_${payload.id}_${Date.now()}`.slice(0, 40)
    const result = await createRazorpayOrder(price, receipt, {
      driverId: String(payload.id), planId: String(planId), purpose: 'subscription',
    })
    if (!result.ok) return withCors({ error: result.error }, 502)

    return withCors({
      orderId: result.order.id,
      keyId: result.keyId,
      amount: result.order.amount,
      currency: result.order.currency,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
