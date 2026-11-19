export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import mongoose from 'mongoose'
import ZoneStaff from '@/models/ZoneStaff'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'
import { cleanFeatures } from '@/lib/zone-features'

async function own(id: string, adminId: any) {
  if (!mongoose.isValidObjectId(id)) return null
  return ZoneStaff.findOne({ _id: id, zoneAdminId: adminId })
}

// PUT { name?, phone?, permissions?, status?, password? }
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'staff', ownerOnly: true, write: true })
  if ('denied' in g) return g.denied
  try {
    const s: any = await own(params.id, g.admin._id)
    if (!s) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const b = await req.json()
    if (b.name !== undefined) s.name = b.name
    if (b.phone !== undefined) s.phone = b.phone
    if (b.permissions !== undefined) s.permissions = cleanFeatures(b.permissions).filter(p => p !== 'staff' && g.features.includes(p))
    if (b.status !== undefined) {
      if (!['active', 'blocked'].includes(b.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
      s.status = b.status
    }
    if (b.password) {
      if (String(b.password).length < 8) return NextResponse.json({ error: 'Password must be at least 8 characters' }, { status: 400 })
      s.password = await bcrypt.hash(String(b.password), 10)
      s.passwordResetRequestedAt = undefined
    }
    await s.save()
    await logZoneActivity(g.admin._id, g.actor, 'staff.update', { name: s.name, status: s.status, permissions: s.permissions, passwordReset: !!b.password })
    const out = s.toObject(); delete out.password
    return NextResponse.json({ staff: out })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'staff', ownerOnly: true, write: true })
  if ('denied' in g) return g.denied
  const s: any = await own(params.id, g.admin._id)
  if (!s) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await s.deleteOne()
  await logZoneActivity(g.admin._id, g.actor, 'staff.delete', { name: s.name, email: s.email })
  return NextResponse.json({ success: true })
}
