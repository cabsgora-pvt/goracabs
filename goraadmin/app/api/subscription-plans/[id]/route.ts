export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// PUT /api/subscription-plans/[id] → update a plan (admin)
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const update: any = {}
    for (const k of ['name', 'price', 'durationDays', 'description', 'benefits',
      'commissionPercentWhileActive', 'services', 'vehicleTypes', 'isActive', 'sortOrder']) {
      if (body[k] !== undefined) update[k] = body[k]
    }
    const plan = await SubscriptionPlan.findByIdAndUpdate(params.id, update, { new: true }).lean()
    if (!plan) return withCors({ error: 'Plan not found' }, 404)
    return withCors({ plan })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// DELETE /api/subscription-plans/[id] → remove a plan (admin)
export async function DELETE(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await SubscriptionPlan.findByIdAndDelete(params.id)
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
