export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import RidePreference from '@/models/RidePreference'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { PREF_SERVICES } from '@/lib/ride-prefs'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'


// PUT { name?, description?, icon?, services?, isActive?, order? }
// DELETE → removes it, and from every driver who offered it.
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'ride_preference.update', String(params.id))
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const b = await req.json().catch(() => ({}))
  const set: any = {}
  if (typeof b.name === 'string' && b.name.trim()) set.name = b.name.trim().slice(0, 40)
  if (typeof b.description === 'string') set.description = b.description.slice(0, 120)
  if (typeof b.icon === 'string' && b.icon) set.icon = b.icon.slice(0, 30)
  if (Array.isArray(b.services)) {
    const s = b.services.filter((x: string) => PREF_SERVICES.includes(x))
    if (s.length) set.services = s
  }
  if (typeof b.isActive === 'boolean') set.isActive = b.isActive
  if (b.order !== undefined && Number.isFinite(Number(b.order))) set.order = Number(b.order)
  await connectDB()
  const p = await RidePreference.findByIdAndUpdate(params.id, { $set: set }, { new: true }).lean()
  if (!p) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ success: true, preference: p })
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'ride_preference.delete', String(params.id))
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const p: any = await RidePreference.findByIdAndDelete(params.id).lean()
  if (p?.key) await Driver.updateMany({ ridePreferences: p.key }, { $pull: { ridePreferences: p.key } })
  return NextResponse.json({ success: true })
}
