export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import ZonePlan from '@/models/ZonePlan'
import { guardAdmin } from '@/lib/admin-guard'
import { cleanFeatures } from '@/lib/zone-features'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const plans = await ZonePlan.find().sort({ isActive: -1, months: 1 }).lean()
    return NextResponse.json({ plans })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

// POST { name, months, price, description?, features? }
export async function POST(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'zone_plan.create', undefined)
  try {
    const b = await req.json()
    const months = Math.floor(Number(b.months)), price = Number(b.price)
    if (!String(b.name || '').trim()) return NextResponse.json({ error: 'Plan name is required' }, { status: 400 })
    if (!(months >= 1 && months <= 60)) return NextResponse.json({ error: 'Months must be between 1 and 60' }, { status: 400 })
    if (!(price >= 0) || !Number.isFinite(price)) return NextResponse.json({ error: 'Enter a valid price' }, { status: 400 })
    await connectDB()
    const plan = await ZonePlan.create({
      name: String(b.name).trim(), months, price, description: b.description || '', isActive: true,
      ...(b.features !== undefined ? { features: cleanFeatures(b.features) } : {}),
    })
    return NextResponse.json({ plan }, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
