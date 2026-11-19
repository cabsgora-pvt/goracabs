export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import ZoneStaff from '@/models/ZoneStaff'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'
import { cleanFeatures } from '@/lib/zone-features'

const MAX_STAFF = 10

// The zone admin's own operators. Only the zone admin manages them, and a
// staff member's permissions are always within the zone admin's own features.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'staff', ownerOnly: true })
  if ('denied' in g) return g.denied
  const staff = await ZoneStaff.find({ zoneAdminId: g.admin._id }).select('-password').sort({ createdAt: -1 }).lean()
  return NextResponse.json({ staff, max: MAX_STAFF })
}

// POST { name, email, phone?, password, permissions[] }
export async function POST(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'staff', ownerOnly: true, write: true })
  if ('denied' in g) return g.denied
  try {
    const b = await req.json()
    const email = String(b.email || '').toLowerCase().trim()
    if (!b.name || !email || !b.password) return NextResponse.json({ error: 'Name, email and password are required' }, { status: 400 })
    if (String(b.password).length < 8) return NextResponse.json({ error: 'Password must be at least 8 characters' }, { status: 400 })
    if ((await ZoneStaff.countDocuments({ zoneAdminId: g.admin._id })) >= MAX_STAFF) {
      return NextResponse.json({ error: `At most ${MAX_STAFF} staff logins` }, { status: 400 })
    }
    // One email, one login, across zone admins and staff.
    if (await ZoneStaff.findOne({ email }) || await ZoneAdmin.findOne({ email })) {
      return NextResponse.json({ error: 'This email is already used' }, { status: 409 })
    }
    const permissions = cleanFeatures(b.permissions).filter(p => p !== 'staff' && g.features.includes(p))
    const staff = await ZoneStaff.create({
      zoneAdminId: g.admin._id, name: b.name, email, phone: b.phone,
      password: await bcrypt.hash(String(b.password), 10), permissions, status: 'active',
    })
    await logZoneActivity(g.admin._id, g.actor, 'staff.create', { name: b.name, email, permissions })
    const out = staff.toObject(); delete out.password
    return NextResponse.json({ staff: out }, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
