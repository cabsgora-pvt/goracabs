export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { requireDriverAuth, requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { rentalExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'
import { cashDueFor } from '@/lib/settlement'
import {
  parseExtraHours, priceRentalExtension, requestExtension, confirmExtension,
  livePendingExtension, MAX_EXTEND_HOURS,
} from '@/lib/ride-extension'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/rental  body.action:
//  driver (the ASSIGNED driver, ride status 'ongoing'):
//  'start'    { lat, lng }        mark start, set rentalStartedAt (idempotent)
//  'ping'     { lat, lng, at? }   accumulate actualKm + actualHours. Implausible
//                                 points are IGNORED (not stored): older than the
//                                 last accepted ping (`at`, ms or ISO), less than
//                                 MIN_PING_GAP_SEC after it, a move faster than
//                                 MAX_KMPH from it (every move is checked — no
//                                 1 km grace any more), or more than MAX_PING_KM.
//                                 actualKm never exceeds MAX_KMPH × actualHours.
//  'wait'     { isWaiting }       toggle halt
//  'extend'   { extraHours }      ASK the rider for 1..12 more hours, priced
//                                 server-side → pendingExtension (nothing changes
//                                 yet). 409 EXTENSION_PENDING while one is live,
//                                 409 EXTENSION_LIMIT after 3 per ride.
//  'end'      { lat, lng }        finalize extras + finalFare. A retry after the
//                                 end returns the same bill: 200 { alreadyEnded }.
//                                 kmAnomaly is set when the tracked km exceed
//                                 1.5x the planned route km (flag only).
//  rider (the ride's rider):
//  'addStop'        { address,lat,lng }  append a destination (accepted/arrived/ongoing)
//  'confirm_extend' { requestedAt, amount }  apply THAT pendingExtension: packageHours
//                                        += h, packageKm += addKm, fare += amount
//                                        (409 EXTENSION_CHANGED when it changed)
//  'decline_extend'                      drop pendingExtension
//
// Every write is an atomic update filtered on status 'ongoing' and rentalPhase
// != 'completed' (a ping racing 'end' can no longer re-open or alter the bill).

const DRIVER_ACTIONS = new Set(['start', 'ping', 'wait', 'extend', 'end'])
const RIDER_ACTIONS = new Set(['addStop', 'confirm_extend', 'decline_extend'])
const RENTAL_PING = { MAX_KMPH: 150, MAX_PING_KM: 30, JITTER_KM: 0.05, MIN_PING_GAP_SEC: 10, ANOMALY_RATIO: 1.5, ROAD_FACTOR: 1.3 }
const OPEN = { status: 'ongoing', rentalPhase: { $ne: 'completed' } }

/** Distance to add for a move from the last anchor, or null when implausible. */
function plausibleKm(ride: any, lat: number, lng: number, at: number): number | null {
  if (ride.rentalLastLat == null || ride.rentalLastLng == null) return 0
  const km = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat, lng })
  if (km <= RENTAL_PING.JITTER_KM) return 0
  if (km > RENTAL_PING.MAX_PING_KM) return null
  const since = ride.rentalLastPingAt || ride.rentalStartedAt
  const hours = since ? Math.max(0, (at - new Date(since).getTime()) / 3_600_000) : 0
  // Every move against the elapsed time; only GPS jitter on top.
  if (km > RENTAL_PING.JITTER_KM + RENTAL_PING.MAX_KMPH * hours) return null
  return km
}

/** actualKm can never exceed what MAX_KMPH allows over the elapsed hours. */
function capKm(km: number, hours: number): number {
  return +Math.max(0, Math.min(km, RENTAL_PING.MAX_KMPH * Math.max(0, hours))).toFixed(2)
}

/** Planned route km: the quoted road distance, or the stops path; null when unknown. */
function expectedKm(ride: any): number | null {
  const quoted = Number(ride.distance) || 0
  let path = 0
  const pts = [{ lat: ride.pickupLat, lng: ride.pickupLng }, ...((ride.rentalStops || []) as any[])]
    .filter(p => p && Number.isFinite(p.lat) && Number.isFinite(p.lng))
  for (let i = 1; i < pts.length; i++) path += distanceKm(pts[i - 1], pts[i])
  const best = Math.max(quoted, path * RENTAL_PING.ROAD_FACTOR)
  return best >= 2 ? +best.toFixed(2) : null
}

function validFix(b: any): { lat: number; lng: number } | null {
  const lat = b?.lat, lng = b?.lng
  if (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)) return null
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) return null
  return { lat, lng }
}

const hoursSince = (t: any, now: Date) => +(((now.getTime() - new Date(t).getTime()) / 3600000)).toFixed(2)

/** Cash the driver collects for this ride (lib/settlement cashDueFor; 0 unless it is a cash ride). */
function cashToCollect(ride: any): number {
  return ride.paymentMode === 'cash' ? cashDueFor(ride) : 0
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json().catch(() => ({}))
    const action = String(b?.action || '')

    if (!DRIVER_ACTIONS.has(action) && !RIDER_ACTIONS.has(action)) {
      return withCors({ error: 'Unknown action' }, 400)
    }

    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.service !== 'rental') return withCors({ error: 'Not a rental ride' }, 400)

    // ── Authorise from the token: the assigned driver for driver actions, the
    // ride's rider for theirs.
    if (DRIVER_ACTIONS.has(action)) {
      const d = requireDriverAuth(req) as any
      if (!d?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.driverId || String(ride.driverId) !== String(d.id)) {
        return withCors({ error: 'Not your ride' }, 403)
      }
    } else {
      const u = requireRider(req) as any
      if (!u?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.riderId || String(ride.riderId) !== String(u.id)) {
        return withCors({ error: 'Not your ride' }, 403)
      }
    }

    // ── Once billed, the rental is closed for changes; a repeated 'end' gets the bill ──
    if (ride.rentalPhase === 'completed' || ride.status === 'completed') {
      if (action === 'end') return ended(ride)
      return withCors({ error: 'Rental already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)
    const okStatus = action === 'addStop' ? ['accepted', 'arrived', 'ongoing'] : ['ongoing']
    if (!okStatus.includes(ride.status)) {
      return withCors({ error: `Not allowed while the ride is ${ride.status}`, code: 'NOT_ONGOING' }, 409)
    }

    const now = new Date()
    const WAIT_DRIFT_KM = 0.5
    const reload = async () => (await Ride.findById(ride._id).lean()) as any

    if (action === 'start') {
      const f = validFix(b)
      const res = await Ride.updateOne({ _id: ride._id, ...OPEN, rentalStartedAt: null }, {
        $set: {
          rentalStartedAt: now, rentalLastPingAt: now, rentalPhase: 'ongoing',
          rentalLastLat: f ? f.lat : ride.pickupLat, rentalLastLng: f ? f.lng : ride.pickupLng,
          actualKm: 0, actualHours: 0,
        },
      })
      return respond(await reload(), !res.modifiedCount, false, null)
    }

    if (action === 'ping') {
      if (!ride.rentalStartedAt) return withCors({ error: 'Rental not started', code: 'NOT_STARTED' }, 409)
      const f = validFix(b)
      const atRaw = b.at != null ? new Date(typeof b.at === 'number' ? b.at : String(b.at)).getTime() : NaN
      const at = Number.isFinite(atRaw) && atRaw <= now.getTime() + 60_000 ? Math.min(atRaw, now.getTime()) : now.getTime()
      const last = ride.rentalLastPingAt ? new Date(ride.rentalLastPingAt).getTime() : 0
      const actualHours = hoursSince(ride.rentalStartedAt, now)
      const set: any = { actualHours }
      let ignoredPing = false
      let reason: string | undefined
      if (f && at <= last) {
        ignoredPing = true; reason = 'STALE'                         // older than the last accepted point
      } else if (f && at - last < RENTAL_PING.MIN_PING_GAP_SEC * 1000) {
        ignoredPing = true; reason = 'TOO_SOON'                      // one ping per 10 s per ride
      } else if (f) {
        const km = plausibleKm(ride, f.lat, f.lng, at)
        if (km == null) {
          ignoredPing = true; reason = 'IMPLAUSIBLE'                 // teleport / impossible speed — not stored
        } else if (ride.isWaiting) {
          // Auto-release a "wait" the vehicle has driven away from.
          if (km > WAIT_DRIFT_KM) {
            Object.assign(set, {
              isWaiting: false, actualKm: capKm((ride.actualKm || 0) + km, actualHours),
              rentalLastLat: f.lat, rentalLastLng: f.lng, rentalLastPingAt: new Date(at),
              rentalPhase: actualHours > (ride.packageHours || 0) ? 'extra_time' : 'ongoing',
            })
          }
        } else if (km > 0) {
          Object.assign(set, {
            actualKm: capKm((ride.actualKm || 0) + km, actualHours),
            rentalLastLat: f.lat, rentalLastLng: f.lng, rentalLastPingAt: new Date(at),
          })
        }
      }
      const km = set.actualKm ?? ride.actualKm ?? 0
      const phase = set.rentalPhase ?? ride.rentalPhase
      if ((actualHours > (ride.packageHours || 0) || km > (ride.packageKm || 0)) && phase === 'ongoing') set.rentalPhase = 'extra_time'
      // Guarded on the anchor read above, so two concurrent pings cannot both
      // add a leg from the same point.
      const res = await Ride.updateOne(
        { _id: ride._id, ...OPEN, rentalLastPingAt: ride.rentalLastPingAt ?? null },
        { $set: set },
      )
      if (!res.matchedCount) { ignoredPing = true; reason = reason || 'RACED' }
      // extraHoursCharge / extraKmCharge are the billed figures and belong to
      // 'end' alone; the live projection below is never persisted.
      return respond(await reload(), false, ignoredPing, null, reason)
    }

    if (action === 'wait') {
      const f = validFix(b)
      const set: any = {
        isWaiting: !!b.isWaiting,
        rentalPhase: b.isWaiting ? 'paused' : ((ride.actualHours || 0) > (ride.packageHours || 0) ? 'extra_time' : 'ongoing'),
      }
      if (f) Object.assign(set, { rentalLastLat: f.lat, rentalLastLng: f.lng, rentalLastPingAt: now }) // reset anchor
      const res = await Ride.updateOne({ _id: ride._id, ...OPEN }, { $set: set })
      if (!res.matchedCount) return withCors({ error: 'Rental already completed' }, 409)
      return respond(await reload(), false, false, null)
    }

    if (action === 'addStop') {
      const f = validFix(b)
      if (!b.address || !f) return withCors({ error: 'address, lat and lng required' }, 400)
      if ((ride.rentalStops || []).length >= 20) return withCors({ error: 'Too many stops' }, 400)
      const res = await Ride.updateOne(
        { _id: ride._id, status: { $in: okStatus }, rentalPhase: { $ne: 'completed' }, 'rentalStops.19': { $exists: false } },
        { $push: { rentalStops: { address: String(b.address).slice(0, 200), lat: f.lat, lng: f.lng, at: now } } },
      )
      if (!res.matchedCount) return withCors({ error: 'This rental changed — refresh and try again', code: 'RENTAL_CHANGED' }, 409)
      return respond(await reload(), false, false, null)
    }

    if (action === 'extend') {
      const extra = parseExtraHours(b.extraHours)
      if (extra == null) return withCors({ error: `extraHours must be a whole number between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      const price = await priceRentalExtension(ride, extra)
      const r = await requestExtension(ride, 'rental', extra, price.amount, price.addKm)
      if (!r.ok) return withCors({ error: r.error, code: r.code, ...(r.pendingExtension ? { pendingExtension: r.pendingExtension } : {}) }, r.status)
      return withCors({ success: true, awaitingRiderConfirmation: true, pendingExtension: r.pendingExtension, basis: price.basis })
    }

    if (action === 'confirm_extend') {
      const r = await confirmExtension(ride._id, 'rental', { requestedAt: b.requestedAt, amount: b.amount },
        (p) => ({ inc: { packageHours: p.hours, packageKm: p.addKm || 0 } }))
      if (!r.ok) return withCors({ error: r.error, code: r.code, ...(r.pendingExtension ? { pendingExtension: r.pendingExtension } : {}) }, r.status)
      const done: any = r.ride
      if (done.actualHours <= done.packageHours && done.actualKm <= done.packageKm && done.rentalPhase === 'extra_time') {
        await Ride.updateOne({ _id: done._id, rentalPhase: 'extra_time' }, { $set: { rentalPhase: 'ongoing' } })
        done.rentalPhase = 'ongoing'
      }
      return respond(done, false, false, null)
    }

    if (action === 'decline_extend') {
      await Ride.updateOne({ _id: ride._id }, { $unset: { pendingExtension: 1 } })
      return withCors({ success: true, declined: true })
    }

    // ── 'end' ──
    if (!ride.rentalStartedAt) return withCors({ error: 'Rental not started' }, 409)
    const f = validFix(b)
    const actualHours = hoursSince(ride.rentalStartedAt, now)
    let actualKm = ride.actualKm || 0
    if (f && !ride.isWaiting) {
      const km = plausibleKm(ride, f.lat, f.lng, now.getTime())
      if (km != null && km > 0) actualKm += km
    }
    actualKm = capKm(actualKm, actualHours)
    const bill: any = { ...ride, actualKm, actualHours }
    const ex = rentalExtras(bill)
    const finalFare = Math.round((ride.fare || 0) + ex.extraHoursCharge + ex.extraKmCharge + (ride.nightChargeRental || 0))
    const kmExpected = expectedKm(ride)
    const set: any = {
      actualKm, actualHours,
      extraHoursCharge: ex.extraHoursCharge, extraKmCharge: ex.extraKmCharge,
      finalFare, totalFare: finalFare + (ride.tip || 0),
      rentalPhase: 'completed', rentalEndedAt: now,
    }
    if (kmExpected != null) {
      set.kmExpected = kmExpected
      if (actualKm > RENTAL_PING.ANOMALY_RATIO * kmExpected) set.kmAnomaly = true
    }
    // Settlement happens in /rides/{id}/complete, never here.
    if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
      set.awaitingPayment = true
      set.paymentStatus = 'pending'
    }
    const done: any = await Ride.findOneAndUpdate(
      { _id: ride._id, ...OPEN },
      { $set: set, $unset: { pendingExtension: 1 } },
      { new: true },
    ).lean()
    if (!done) {
      const cur = await reload()
      if (cur && (cur.rentalPhase === 'completed' || cur.status === 'completed')) return ended(cur)
      return withCors({ error: `Not allowed while the ride is ${cur?.status}`, code: 'NOT_ONGOING' }, 409)
    }
    return ended(done, false)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

/** The 'end' answer (also for a retry after the end). */
function ended(ride: any, already = true) {
  return respond(ride, false, false, null, undefined, { ...(already ? { alreadyEnded: true } : {}), cashToCollect: cashToCollect(ride), kmAnomaly: !!ride.kmAnomaly })
}

function respond(ride: any, alreadyStarted: boolean, ignoredPing: boolean, pendingExtension: any, ignoredReason?: string, extra: Record<string, any> = {}) {
  const live = rentalExtras(ride)
  return withCors({
    success: true,
    alreadyStarted,
    ...(ignoredPing ? { ignoredPing: true, ...(ignoredReason ? { ignoredReason } : {}) } : {}),
    ...extra,
    rental: {
      elapsedSec: secondsSince(ride.rentalStartedAt),
      liveExtraHours: live.extraHours,
      liveExtraKm: live.extraKm,
      liveExtraCharge: Math.round(live.total),
      phase: ride.rentalPhase, isWaiting: ride.isWaiting,
      actualHours: ride.actualHours, actualKm: ride.actualKm,
      packageHours: ride.packageHours, packageKm: ride.packageKm,
      extraHoursCharge: ride.extraHoursCharge, extraKmCharge: ride.extraKmCharge,
      nightCharge: ride.nightChargeRental || 0,
      baseFare: ride.fare || 0,
      finalFare: ride.finalFare,
      totalFare: ride.totalFare,
      awaitingPayment: !!ride.awaitingPayment,
      status: ride.status,
      rentalStartedAt: ride.rentalStartedAt,
      rentalStops: ride.rentalStops || [],
      pendingExtension: pendingExtension ?? livePendingExtension(ride),
      ...(ride.rentalPhase === 'completed' ? { kmAnomaly: !!ride.kmAnomaly, kmExpected: ride.kmExpected ?? null } : {}),
    },
  })
}
