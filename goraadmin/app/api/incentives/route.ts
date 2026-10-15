export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import IncentiveRule from '@/models/IncentiveRule'
import { guardAdmin } from '@/lib/admin-guard'

// Admin CRUD for driver incentives. Drivers read their own progress from
// /api/auth/driver/incentives.
export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const rules = await IncentiveRule.find().sort({ createdAt: -1 }).lean()
    return NextResponse.json({ rules })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const b = await req.json()
    if (!b.title || !b.target) {
      return NextResponse.json({ error: 'Title and target are required' }, { status: 400 })
    }
    const rule = await IncentiveRule.create({
      title: b.title,
      description: b.description || '',
      metric: b.metric === 'earnings' ? 'earnings' : 'rides',
      target: Number(b.target) || 0,
      period: ['day', 'week', 'month'].includes(b.period) ? b.period : 'day',
      service: b.service || '',
      vehicleTypeName: b.vehicleTypeName || '',
      zoneId: b.zoneId || '',
      startHour: Number(b.startHour) || 0,
      endHour: Number(b.endHour) || 0,
      rewardAmount: Number(b.rewardAmount) || 0,
      isActive: b.isActive !== false,
      validFrom: b.validFrom ? new Date(b.validFrom) : undefined,
      validTo: b.validTo ? new Date(b.validTo) : undefined,
    })
    return NextResponse.json(rule, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 400 })
  }
}
