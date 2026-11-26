export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import SupportTicket from '@/models/SupportTicket'
import SOSAlert, { SOS_OPEN_STATUSES } from '@/models/SOSAlert'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import { pointInPolygon } from '@/lib/geo'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Tickets and SOS alerts carry no zone of their own. One belongs to a zone
// through its ride, else its driver (tickets) or its position (SOS), else the
// zone name a ticket was filed under — the FIRST of these that has a zone
// decides (a ticket whose ride is in another zone is not ours even if the
// driver is).
async function zoneResolver(zoneIds: string[]) {
  const zones: any[] = await Zone.find({ _id: { $in: zoneIds } }).select('name polygonPath').lean()
  const names = new Set(zones.map(z => String(z.name || '').toLowerCase()))
  return {
    zones,
    names,
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
        return inPolygons(zones, item.lat, item.lng)
      }
      return !!item.zoneName && names.has(item.zoneName.toLowerCase())
    },
  }
}

const inPolygons = (zones: any[], lat: number, lng: number) =>
  zones.some(z => (z.polygonPath?.length || 0) >= 3 && pointInPolygon({ lat, lng }, z.polygonPath))

/** Of the ride / driver ids a collection references, which have a zone, and which of those are ours. */
async function zonedRefs(Model: any, ids: any[], zoneIds: string[]) {
  const clean = ids.filter(Boolean)
  const rows: any[] = clean.length ? await Model.find({ _id: { $in: clean } }).select('zoneId').lean() : []
  const zoned = rows.filter(r => r.zoneId)
  return {
    zoned: zoned.map(r => r._id),
    ours: zoned.filter(r => zoneIds.includes(String(r.zoneId))).map(r => r._id),
  }
}

// GET ?ticketPage&sosPage&limit — tickets and SOS alerts of the zone admin's
// zones, newest first, filtered in Mongo (no per-item lookups, no cap on how
// far back): the rides / drivers the collections reference are read once, in
// bulk, and the zone rule becomes one $or query. SOS alerts placed only by
// position are narrowed by the zones' bounding box in Mongo, then checked
// against the polygon.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'support' })
  if ('denied' in g) return g.denied
  try {
    const sp = req.nextUrl.searchParams
    const limit = parsePaging(sp, 100).limit
    const ticketPage = Math.max(1, Math.floor(Number(sp.get('ticketPage')) || 1))
    const sosPage = Math.max(1, Math.floor(Number(sp.get('sosPage')) || 1))
    const { zones, names } = await zoneResolver(g.zoneIds)

    // ── Tickets ──
    const [tRideIds, tDriverIds] = await Promise.all([SupportTicket.distinct('rideId'), SupportTicket.distinct('driverId')])
    const [tr, td] = await Promise.all([zonedRefs(Ride, tRideIds, g.zoneIds), zonedRefs(Driver, tDriverIds, g.zoneIds)])
    const nameMatch = Array.from(names).filter(Boolean).map(n => ({ zoneName: { $regex: `^${escapeRegex(n, 200)}$`, $options: 'i' } }))
    const noRideZone = { rideId: { $nin: tr.zoned } }
    const ticketQ: any = { $or: [
      { rideId: { $in: tr.ours } },
      { ...noRideZone, driverId: { $in: td.ours } },
      ...(nameMatch.length ? [{ ...noRideZone, driverId: { $nin: td.zoned }, $or: nameMatch }] : []),
    ] }

    // ── SOS ──
    const sRideIds = await SOSAlert.distinct('rideId')
    const sr = await zonedRefs(Ride, sRideIds, g.zoneIds)
    const pts = zones.flatMap(z => (z.polygonPath?.length || 0) >= 3 ? z.polygonPath : [])
    const bbox = pts.length ? {
      lat: { $gte: Math.min(...pts.map((p: any) => p.lat)), $lte: Math.max(...pts.map((p: any) => p.lat)) },
      lng: { $gte: Math.min(...pts.map((p: any) => p.lng)), $lte: Math.max(...pts.map((p: any) => p.lng)) },
    } : null
    const sosQ: any = { $or: [
      { rideId: { $in: sr.ours } },
      ...(bbox ? [{ rideId: { $nin: sr.zoned }, ...bbox }] : []),
    ] }

    const [tickets, ticketTotal, sosRows] = await Promise.all([
      SupportTicket.find(ticketQ).sort({ createdAt: -1, _id: -1 }).skip((ticketPage - 1) * limit).limit(limit).lean(),
      SupportTicket.countDocuments(ticketQ),
      // Candidates are ride-matched (exact) or inside the bounding box; the
      // box ones still need the polygon test, so this set is read whole —
      // only _id / ride / position, then the page is fetched by id.
      SOSAlert.find(sosQ).select('_id rideId lat lng status createdAt').sort({ createdAt: -1, _id: -1 }).lean(),
    ])
    const ours = new Set(sr.ours.map(String))
    const sosIds = (sosRows as any[]).filter(s =>
      (s.rideId && ours.has(String(s.rideId))) ||
      (typeof s.lat === 'number' && typeof s.lng === 'number' && inPolygons(zones, s.lat, s.lng)))
    const sosActive = sosIds.filter(s => SOS_OPEN_STATUSES.includes(s.status)).length
    const pageIds = sosIds.slice((sosPage - 1) * limit, sosPage * limit).map(s => s._id)
    const sos = pageIds.length ? await SOSAlert.find({ _id: { $in: pageIds } }).sort({ createdAt: -1, _id: -1 }).lean() : []

    return NextResponse.json({
      tickets, sos,
      ticketTotal, sosTotal: sosIds.length, sosActive,
      ticketPage, sosPage, limit,
    })
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
      if (!['active', 'acknowledged', 'resolved'].includes(b.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
      const by = `zone:${g.actor?.name || g.admin?.email || 'zone admin'}`
      if (b.status === 'resolved' && s.status !== 'resolved') {
        s.resolvedAt = new Date(); s.resolvedBy = by
        if (typeof b.note === 'string' && b.note.trim()) s.resolutionNote = b.note.trim().slice(0, 1000)
        if (!s.acknowledgedAt) { s.acknowledgedAt = s.resolvedAt; s.acknowledgedBy = by }
      }
      if (b.status === 'acknowledged' && s.status === 'active') { s.acknowledgedAt = new Date(); s.acknowledgedBy = by }
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
