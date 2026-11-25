export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZonePlan from '@/models/ZonePlan'
import { guardAdmin } from '@/lib/admin-guard'
import { cleanFeatures } from '@/lib/zone-features'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

// PUT { name?, months?, price?, description?, isActive? }
// Editing a plan changes only future sales; payments already recorded keep the
// name, months and amount they were made with.
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'zone_plan.update', String(params.id))
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const b = await req.json()
    const set: any = {}
    if (b.name !== undefined) {
      if (!String(b.name).trim()) return NextResponse.json({ error: 'Plan name is required' }, { status: 400 })
      set.name = String(b.name).trim()
    }
    if (b.months !== undefined) {
      const m = Math.floor(Number(b.months))
      if (!(m >= 1 && m <= 60)) return NextResponse.json({ error: 'Months must be between 1 and 60' }, { status: 400 })
      set.months = m
    }
    if (b.price !== undefined) {
      const p = Number(b.price)
      if (!(p >= 0) || !Number.isFinite(p)) return NextResponse.json({ error: 'Enter a valid price' }, { status: 400 })
      set.price = p
    }
    if (b.description !== undefined) set.description = String(b.description)
    if (b.isActive !== undefined) set.isActive = !!b.isActive
    // New features reach zone admins at their next renewal; the super admin can
    // also change a zone admin's features directly on their profile.
    if (b.features !== undefined) set.features = cleanFeatures(b.features)
    await connectDB()
    const plan = await ZonePlan.findByIdAndUpdate(params.id, { $set: set }, { new: true }).lean()
    if (!plan) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    return NextResponse.json({ plan })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'zone_plan.delete', String(params.id))
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    await ZonePlan.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
