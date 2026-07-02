export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/subscription-plans        → all plans (admin)
// GET /api/subscription-plans?active=1 → only active plans (driver app)
export async function GET(req: NextRequest) {
  try {
    await connectDB()
    const activeOnly = req.nextUrl.searchParams.get('active') === '1'
    const filter = activeOnly ? { isActive: true } : {}
    const plans = await SubscriptionPlan.find(filter).sort({ sortOrder: 1, price: 1 }).lean()
    return withCors({ plans })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST /api/subscription-plans → create a plan (admin)
export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const plan = await SubscriptionPlan.create({
      name: body.name || 'Plan',
      price: Number(body.price) || 0,
      durationDays: Number(body.durationDays) || 30,
      description: body.description || '',
      benefits: Array.isArray(body.benefits) ? body.benefits : [],
      commissionPercentWhileActive: Number(body.commissionPercentWhileActive) || 0,
      services: Array.isArray(body.services) ? body.services : [],
      vehicleTypes: Array.isArray(body.vehicleTypes) ? body.vehicleTypes : [],
      isActive: body.isActive !== false,
      sortOrder: Number(body.sortOrder) || 0,
    })
    return withCors({ plan })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
