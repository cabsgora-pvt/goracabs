export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'

// POST { current, next } — the signed-in zone admin or staff member changes
// their own password. Allowed during the read-only grace period too.
export async function POST(req: NextRequest) {
  const g = await guardZoneAdmin(req)
  if ('denied' in g) return g.denied
  if (g.impersonatedBy) return NextResponse.json({ error: 'Not while viewing as the zone admin' }, { status: 403 })
  try {
    const { current, next } = await req.json()
    if (!next || String(next).length < 8) return NextResponse.json({ error: 'New password must be at least 8 characters' }, { status: 400 })
    const doc: any = g.actor.type === 'staff' ? await ZoneStaff.findById(g.actor.id) : await ZoneAdmin.findById(g.admin._id)
    if (!doc || !(await bcrypt.compare(String(current || ''), doc.password))) {
      return NextResponse.json({ error: 'Current password is wrong' }, { status: 400 })
    }
    doc.password = await bcrypt.hash(String(next), 10)
    doc.passwordResetRequestedAt = undefined
    await doc.save()
    await logZoneActivity(g.admin._id, g.actor, 'password.changed')
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
