export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { applyPlan, logZoneActivity, publicZoneAdmin, zoneNameMap, zonesTakenByOthers } from '@/lib/zone-admin'

export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const [admins, names] = await Promise.all([
      ZoneAdmin.find().select('-password').sort({ createdAt: -1 }).lean(),
      zoneNameMap(),
    ])
    return NextResponse.json({ zoneAdmins: (admins as any[]).map(a => publicZoneAdmin(a, names)) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

// POST { name, email, phone, password, businessName?, address?, gstNumber?, zoneIds[],
//        planId?, paymentRef?, notes? }  — a plan made under Subscription Plans
export async function POST(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const b = await req.json()
    const email = String(b.email || '').toLowerCase().trim()
    if (!b.name || !email || !b.password) {
      return NextResponse.json({ error: 'Name, email and password are required' }, { status: 400 })
    }
    if (String(b.password).length < 8) {
      return NextResponse.json({ error: 'Password must be at least 8 characters' }, { status: 400 })
    }
    if (await ZoneAdmin.findOne({ email }) || await ZoneStaff.findOne({ email })) {
      return NextResponse.json({ error: 'A zone admin with this email already exists' }, { status: 409 })
    }
    const zoneIds: string[] = Array.isArray(b.zoneIds) ? b.zoneIds.map(String) : []
    const { taken } = await zonesTakenByOthers(zoneIds)
    if (taken.length) {
      return NextResponse.json({ error: 'One of these zones already has a zone admin. Remove it from them first.' }, { status: 409 })
    }

    const doc: any = {
      name: b.name, email, phone: b.phone, businessName: b.businessName, address: b.address, gstNumber: b.gstNumber,
      password: await bcrypt.hash(String(b.password), 10),
      zoneIds,
      status: 'active',
      payments: [],
    }
    // Without a plan the account exists but cannot sign in until one is given.
    if (b.planId) {
      const err = await applyPlan(doc, b.planId, { paymentRef: b.paymentRef, notes: b.notes, recordedBy: requireAdmin(req)?.email })
      if (err) return NextResponse.json({ error: err }, { status: 400 })
    }
    const created = await ZoneAdmin.create(doc)
    await logZoneActivity(created._id, { type: 'super_admin', id: '', name: requireAdmin(req)?.email || 'super admin' }, 'admin.create',
      { zones: zoneIds.length, plan: doc.payments[0]?.planName })
    const names = await zoneNameMap()
    return NextResponse.json({ zoneAdmin: publicZoneAdmin(created.toObject(), names) }, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
