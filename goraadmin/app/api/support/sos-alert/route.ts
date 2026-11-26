export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSAlert from '@/models/SOSAlert'
import mongoose from 'mongoose'
import { requireAdmin, requireDriverAuth, requireRider } from '@/lib/auth'
import { NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { auditAdmin } from '@/lib/admin-audit'
import { parsePaging } from '@/lib/list-params'
import { SOS_OPEN_STATUSES } from '@/models/SOSAlert'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { limitHit } from '@/lib/rate-limit'
import { escalateSos } from '@/lib/sos-escalate'

const SOS_RATE = { LIMIT: 3, WINDOW_MS: 10 * 60_000 }
const SOS_DEDUPE_MS = 2 * 60_000

export async function OPTIONS() {
  return corsOptions()
}

// POST — raise an SOS alert (called by rider or driver apps when SOS is tapped).
// GET  — admin lists alerts (newest first, with ride details).
export async function POST(req: NextRequest) {
  try {
    // Who raised it comes from the token, never the body: a rider token is
    // 'user', a driver token 'driver', and the name/phone are read from that
    // account. (They used to be whatever the app sent.)
    const asDriver = requireDriverAuth(req) as any
    const asRider = asDriver?.id ? null : (requireRider(req) as any)
    if (!asDriver?.id && !asRider?.id) return withCors({ error: 'Unauthorized' }, 401)
    const b = await req.json().catch(() => ({}))
    await connectDB()
    const person: any = asDriver?.id
      ? await Driver.findById(asDriver.id).select('name phone').lean()
      : await User.findById(asRider.id).select('name phone').lean()
    if (!person) return withCors({ error: 'Account not found' }, 404)

    // A ride id is kept only when the caller is on that ride.
    let rideId: any = undefined
    if (b.rideId && mongoose.isValidObjectId(String(b.rideId))) {
      const r: any = await Ride.findById(b.rideId).select('riderId driverId').lean()
      const mine = r && (asDriver?.id ? String(r.driverId || '') === String(asDriver.id) : String(r.riderId || '') === String(asRider.id))
      if (mine) rideId = r._id
    }
    const triggeredBy = asDriver?.id ? 'driver' : 'user'
    // A repeat tap of the same SOS (same account, same ride) within 2 min is
    // the same emergency: answer with the alert already raised.
    const dup: any = await SOSAlert.findOne({
      triggeredBy, phone: person.phone || '', rideId: rideId ?? null, status: { $in: SOS_OPEN_STATUSES },
      createdAt: { $gte: new Date(Date.now() - SOS_DEDUPE_MS) },
    }).sort({ createdAt: -1 }).select('_id').lean()
    if (dup) return withCors({ success: true, id: dup._id, deduped: true })
    // 3 alerts per 10 min per account — enough for any real emergency, not a flood.
    const accountId = String(asDriver?.id || asRider?.id)
    if (!(await limitHit(`sos:${triggeredBy}:${accountId}`, SOS_RATE.LIMIT, SOS_RATE.WINDOW_MS))) {
      return withCors({ error: 'SOS already sent. Our team has been alerted — if you are in danger call 112.', code: 'RATE_LIMITED' }, 429)
    }
    const num = (v: any, lim: number) => (typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= lim ? v : undefined)
    const alert = await SOSAlert.create({
      rideId,
      triggeredBy,
      name: person.name || '',
      phone: person.phone || '',
      lat: num(b.lat, 90),
      lng: num(b.lng, 180),
      address: typeof b.address === 'string' ? b.address.slice(0, 300) : '',
      status: 'active',
    })
    // Escalation (admins / SOS contacts) never delays or fails the answer.
    escalateSos(alert, { personId: accountId }).catch(() => {})
    return withCors({ success: true, id: alert._id })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}

// GET ?status=active|acknowledged|resolved|open (open = not resolved)&page&limit
// Admin list. Unresolved first (active, then acknowledged), newest first within
// each; then resolved, newest first. Carries the ride's rider/driver phones so
// the page can call either. Counts per status for the filter chips.
const RANK = { $switch: { branches: [
  { case: { $eq: ['$status', 'active'] }, then: 0 },
  { case: { $eq: ['$status', 'acknowledged'] }, then: 1 },
], default: 2 } }

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 50)
    const st = sp.get('status') || ''
    const match: any = {}
    if (st === 'open') match.status = { $in: SOS_OPEN_STATUSES }
    else if (['active', 'acknowledged', 'resolved'].includes(st)) match.status = st
    const [rows, total, byStatus] = await Promise.all([
      SOSAlert.aggregate([
        { $match: match },
        { $addFields: { _rank: RANK } },
        { $sort: { _rank: 1, createdAt: -1 } },
        { $skip: skip }, { $limit: limit },
        { $project: { _rank: 0 } },
      ]),
      SOSAlert.countDocuments(match),
      SOSAlert.aggregate([{ $group: { _id: '$status', n: { $sum: 1 } } }]),
    ])
    const counts: Record<string, number> = { active: 0, acknowledged: 0, resolved: 0 }
    for (const b of byStatus) counts[b._id] = b.n
    const rideIds = rows.map((a: any) => a.rideId).filter(Boolean)
    const rides: any[] = rideIds.length
      ? await Ride.find({ _id: { $in: rideIds } }).select('service pickupAddress dropAddress status driverName riderName riderPhone driverPhone').lean()
      : []
    const byId = new Map(rides.map(r => [String(r._id), r]))
    // rideId stays the populated ride, as the page always read it.
    const alerts = rows.map((a: any) => ({ ...a, rideId: (a.rideId && byId.get(String(a.rideId))) || a.rideId || null }))
    return NextResponse.json({ alerts, total, page, limit, counts })
  } catch (error: any) {
    return NextResponse.json({ error: error.message || 'Server error' }, { status: 500 })
  }
}

// PATCH { id, action: 'acknowledge' | 'resolve', note? }
// acknowledge: active → acknowledged. resolve (note required): active or
// acknowledged → resolved. Records who and when. Idempotent: repeating an
// action that already happened changes nothing and answers 200 unchanged
// (the first admin's name and time are kept); acknowledging a resolved alert
// is a no-op too.
export async function PATCH(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const admin: any = requireAdmin(req)
    const by = String(admin?.email || 'admin')
    const b = await req.json().catch(() => ({}))
    if (!mongoose.isValidObjectId(String(b.id || ''))) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const action = String(b.action || '')
    if (action !== 'acknowledge' && action !== 'resolve') return NextResponse.json({ error: 'action must be acknowledge or resolve' }, { status: 400 })
    const note = typeof b.note === 'string' ? b.note.trim().slice(0, 1000) : ''
    if (action === 'resolve' && note.length < 3) return NextResponse.json({ error: 'Write a short note on how it was resolved' }, { status: 400 })
    await connectDB()
    const now = new Date()
    const updated: any = action === 'acknowledge'
      ? await SOSAlert.findOneAndUpdate({ _id: b.id, status: 'active' },
          { $set: { status: 'acknowledged', acknowledgedAt: now, acknowledgedBy: by } }, { new: true }).lean()
      : await SOSAlert.findOneAndUpdate({ _id: b.id, status: { $in: SOS_OPEN_STATUSES } },
          { $set: { status: 'resolved', resolvedAt: now, resolvedBy: by, resolutionNote: note } }, { new: true }).lean()
    if (!updated) {
      const cur: any = await SOSAlert.findById(b.id).lean()
      if (!cur) return NextResponse.json({ error: 'Not found' }, { status: 404 })
      return NextResponse.json({ success: true, unchanged: true, alert: cur })
    }
    // An alert resolved straight from active was seen at the same moment.
    if (action === 'resolve' && !updated.acknowledgedAt) {
      await SOSAlert.updateOne({ _id: updated._id, acknowledgedAt: { $exists: false } }, { $set: { acknowledgedAt: now, acknowledgedBy: by } })
      updated.acknowledgedAt = now; updated.acknowledgedBy = by
    }
    await auditAdmin(req, admin, `sos.${action}`, {
      target: `sos:${updated._id}`,
      summary: `SOS ${action === 'resolve' ? 'resolved' : 'acknowledged'} — ${updated.name || ''} ${String(updated.phone || '').slice(-4)}`,
      details: action === 'resolve' ? { note } : undefined,
    })
    return NextResponse.json({ success: true, alert: updated })
  } catch (error: any) {
    return NextResponse.json({ error: error.message || 'Server error' }, { status: 500 })
  }
}
