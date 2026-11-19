export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import SupportTicket from '@/models/SupportTicket'
import SOSAlert from '@/models/SOSAlert'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import { pointInPolygon } from '@/lib/geo'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'

// Tickets and SOS alerts carry no zone of their own. One belongs to a zone
// through its ride, else its driver (tickets) or its position (SOS), else the
// zone name a ticket was filed under.
async function zoneResolver(zoneIds: string[]) {
  const zones: any[] = await Zone.find({ _id: { $in: zoneIds } }).select('name polygonPath').lean()
  const names = new Set(zones.map(z => String(z.name || '').toLowerCase()))
  return {
    zones,
    inZone: async (item: { rideId?: any; driverId?: any; zoneName?: string; lat?: number; lng?: number }) => {
      if (item.rideId) {
        const r: any = await Ride.findById(item.rideId).select('zoneId').lean()
        if (r?.zoneId) return zoneIds.includes(String(r.zoneId))
      }
      if (item.driverId) {
        const d: any = await Driver.findById(item.driverId).select('zoneId').lean()
        if (d?.zoneId) return zoneIds.includes(String(d.zoneId))
      }
      if (item.lat != null && item.lng != null) {
        return zones.some(z => (z.polygonPath?.length || 0) >= 3 && pointInPolygon({ lat: item.lat!, lng: item.lng! }, z.polygonPath))
      }
      return !!item.zoneName && names.has(item.zoneName.toLowerCase())
    },
  }
}

export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'support' })
  if ('denied' in g) return g.denied
  try {
    const { inZone } = await zoneResolver(g.zoneIds)
    const [tickets, sos] = await Promise.all([
      SupportTicket.find().sort({ createdAt: -1 }).limit(300).lean(),
      SOSAlert.find().sort({ createdAt: -1 }).limit(200).lean(),
    ])
    const myTickets: any[] = [], mySos: any[] = []
    for (const t of tickets as any[]) if (await inZone(t)) myTickets.push(t)
    for (const s of sos as any[]) if (await inZone(s)) mySos.push(s)
    return NextResponse.json({ tickets: myTickets, sos: mySos })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

// PATCH { kind: 'ticket' | 'sos', id, status?, reply? }
export async function PATCH(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'support', write: true })
  if ('denied' in g) return g.denied
  try {
    const b = await req.json()
    if (!mongoose.isValidObjectId(b.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const { inZone } = await zoneResolver(g.zoneIds)
    if (b.kind === 'sos') {
      const s: any = await SOSAlert.findById(b.id)
      if (!s || !(await inZone(s))) return NextResponse.json({ error: 'Not found in your zone' }, { status: 404 })
      if (b.status !== 'resolved' && b.status !== 'active') return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
      s.status = b.status; await s.save()
      await logZoneActivity(g.admin._id, g.actor, 'sos.' + b.status, { name: s.name, phone: s.phone })
      return NextResponse.json({ sos: s })
    }
    const t: any = await SupportTicket.findById(b.id)
    if (!t || !(await inZone(t))) return NextResponse.json({ error: 'Not found in your zone' }, { status: 404 })
    if (b.status) {
      if (!['open', 'in_progress', 'resolved', 'closed'].includes(b.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
      t.status = b.status
    }
    if (b.reply && String(b.reply).trim()) {
      t.messages.push({ sender: 'admin', message: String(b.reply).trim().slice(0, 2000), sentAt: new Date() })
    }
    await t.save()
    await logZoneActivity(g.admin._id, g.actor, 'ticket.update', { subject: t.subject, status: t.status, replied: !!b.reply })
    return NextResponse.json({ ticket: t })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
