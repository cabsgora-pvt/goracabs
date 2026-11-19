export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import Zone from '@/models/Zone'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'

// PUT { zoneId, supportPhone } — the helpline riders in this zone see.
export async function PUT(req: NextRequest) {
  const g = await guardZoneAdmin(req, { ownerOnly: true, write: true })
  if ('denied' in g) return g.denied
  try {
    const b = await req.json()
    const zoneId = String(b.zoneId || '')
    if (!g.zoneIds.includes(zoneId)) return NextResponse.json({ error: 'Not your zone' }, { status: 403 })
    const phone = String(b.supportPhone || '').trim()
    if (phone && !/^\+?[0-9 \-]{8,16}$/.test(phone)) return NextResponse.json({ error: 'Enter a valid phone number' }, { status: 400 })
    const z: any = await Zone.findByIdAndUpdate(zoneId, { $set: { supportPhone: phone } }, { new: true }).select('name supportPhone').lean()
    await logZoneActivity(g.admin._id, g.actor, 'zone.support_phone', { zone: z?.name, supportPhone: phone })
    return NextResponse.json({ zone: z })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
