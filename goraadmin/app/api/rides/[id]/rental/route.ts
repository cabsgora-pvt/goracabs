export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { requireDriverAuth, requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { rentalExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'
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
//                                 last accepted ping (`at`, ms or ISO), a jump
//                                 implying > MAX_KMPH since the last ping, or more
//                                 than MAX_PING_KM in one ping.
//  'wait'     { isWaiting }       toggle halt
//  'extend'   { extraHours }      ASK the rider for 1..12 more hours, priced
//                                 server-side → pendingExtension (nothing changes yet)
//  'end'      { lat, lng }        finalize extras + finalFare
//  rider (the ride's rider):
//  'addStop'        { address,lat,lng }  append a destination (accepted/arrived/ongoing)
//  'confirm_extend'                      apply pendingExtension: packageHours += h,
//                                        packageKm += addKm, fare += amount
//  'decline_extend'                      drop pendingExtension

const DRIVER_ACTIONS = new Set(['start', 'ping', 'wait', 'extend', 'end'])
const RIDER_ACTIONS = new Set(['addStop', 'confirm_extend', 'decline_extend'])
const RENTAL_PING = { MAX_KMPH: 150, MAX_PING_KM: 30, JITTER_KM: 0.02 }

/** Distance to add for a move from the last anchor, or null when implausible. */
function plausibleKm(ride: any, lat: number, lng: number, at: number): number | null {
  if (ride.rentalLastLat == null || ride.rentalLastLng == null) return 0
  const km = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat, lng })
  if (km <= RENTAL_PING.JITTER_KM) return 0
  if (km > RENTAL_PING.MAX_PING_KM) return null
  const since = ride.rentalLastPingAt || ride.rentalStartedAt
  if (since) {
    const hours = Math.max(0, (at - new Date(since).getTime()) / 3_600_000)
    // A ~1 km tolerance absorbs a GPS fix landing a little late or early.
    if (km > 1 && (hours <= 0 || km / hours > RENTAL_PING.MAX_KMPH)) return null
  }
  return km
}

function validFix(b: any): { lat: number; lng: number } | null {
  const lat = b?.lat, lng = b?.lng
  if (typeof lat !== 'number' || typeof lng !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lng)) return null
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) return null
  return { lat, lng }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json().catch(() => ({}))
    const action = String(b?.action || '')

    if (!DRIVER_ACTIONS.has(action) && !RIDER_ACTIONS.has(action)) {
      return withCors({ error: 'Unknown action' }, 400)
    }

    const ride: any = await Ride.findById(params.id)
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

    // ── Idempotency: once billed, the rental is closed for changes ──
    if (ride.rentalPhase === 'completed' || ride.status === 'completed') {
      return withCors({ error: 'Rental already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)
    const okStatus = action === 'addStop' ? ['accepted', 'arrived', 'ongoing'] : ['ongoing']
    if (!okStatus.includes(ride.status)) {
      return withCors({ error: `Not allowed while the ride is ${ride.status}`, code: 'NOT_ONGOING' }, 409)
    }

    const now = new Date()
    const WAIT_DRIFT_KM = 0.5
    let alreadyStarted = false
    let ignoredPing = false
    let pendingExtension: any = livePendingExtension(ride)

    if (action === 'start') {
      if (ride.rentalStartedAt) {
        alreadyStarted = true
      } else {
        const f = validFix(b)
        ride.rentalStartedAt = now
        ride.rentalLastPingAt = now
        ride.rentalPhase = 'ongoing'
        ride.rentalLastLat = f ? f.lat : ride.pickupLat
        ride.rentalLastLng = f ? f.lng : ride.pickupLng
        ride.actualKm = 0
        ride.actualHours = 0
      }
    } else if (action === 'ping') {
      if (!ride.rentalStartedAt) return withCors({ error: 'Rental not started', code: 'NOT_STARTED' }, 409)
      const f = validFix(b)
      const atRaw = b.at != null ? new Date(typeof b.at === 'number' ? b.at : String(b.at)).getTime() : NaN
      const at = Number.isFinite(atRaw) && atRaw <= now.getTime() + 60_000 ? Math.min(atRaw, now.getTime()) : now.getTime()
      const last = ride.rentalLastPingAt ? new Date(ride.rentalLastPingAt).getTime() : 0
      if (f && at <= last) {
        ignoredPing = true          // older than the last accepted point
      } else if (f) {
        const km = plausibleKm(ride, f.lat, f.lng, at)
        if (km == null) {
          ignoredPing = true        // teleport / impossible speed — not stored
        } else if (ride.isWaiting) {
          // Auto-release a "wait" the vehicle has driven away from.
          if (km > WAIT_DRIFT_KM) {
            ride.isWaiting = false
            ride.actualKm = +(ride.actualKm + km).toFixed(2)
            ride.rentalLastLat = f.lat; ride.rentalLastLng = f.lng
            ride.rentalLastPingAt = new Date(at)
            ride.rentalPhase = ride.actualHours > ride.packageHours ? 'extra_time' : 'ongoing'
          }
        } else if (km > 0) {
          ride.actualKm = +(ride.actualKm + km).toFixed(2)
          ride.rentalLastLat = f.lat; ride.rentalLastLng = f.lng
          ride.rentalLastPingAt = new Date(at)
        }
      }
      ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)
      if (ride.actualHours > ride.packageHours || ride.actualKm > ride.packageKm) {
        if (ride.rentalPhase === 'ongoing') ride.rentalPhase = 'extra_time'
      }
      // extraHoursCharge / extraKmCharge are the billed figures and belong to
      // 'end' alone; the live projection below is never persisted.
    } else if (action === 'wait') {
      ride.isWaiting = !!b.isWaiting
      ride.rentalPhase = b.isWaiting ? 'paused' : (ride.actualHours > ride.packageHours ? 'extra_time' : 'ongoing')
      const f = validFix(b)
      if (f) { ride.rentalLastLat = f.lat; ride.rentalLastLng = f.lng; ride.rentalLastPingAt = now } // reset anchor
    } else if (action === 'addStop') {
      const f = validFix(b)
      if (!b.address || !f) return withCors({ error: 'address, lat and lng required' }, 400)
      ride.rentalStops = ride.rentalStops || []
      if (ride.rentalStops.length >= 20) return withCors({ error: 'Too many stops' }, 400)
      ride.rentalStops.push({ address: String(b.address).slice(0, 200), lat: f.lat, lng: f.lng, at: now })
    } else if (action === 'extend') {
      const extra = parseExtraHours(b.extraHours)
      if (extra == null) return withCors({ error: `extraHours must be a whole number between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      const price = await priceRentalExtension(ride, extra)
      pendingExtension = await requestExtension(ride, 'rental', extra, price.amount, price.addKm)
      return withCors({ success: true, awaitingRiderConfirmation: true, pendingExtension, basis: price.basis })
    } else if (action === 'confirm_extend') {
      const done: any = await confirmExtension(ride._id, 'rental', (p) => ({ inc: { packageHours: p.hours, packageKm: p.addKm || 0 } }))
      if (!done) return withCors({ error: 'No extension is waiting for your confirmation', code: 'NO_PENDING_EXTENSION' }, 409)
      if (done.actualHours <= done.packageHours && done.actualKm <= done.packageKm && done.rentalPhase === 'extra_time') {
        await Ride.updateOne({ _id: done._id, rentalPhase: 'extra_time' }, { $set: { rentalPhase: 'ongoing' } })
        done.rentalPhase = 'ongoing'
      }
      return respond(done, false, false, null)
    } else if (action === 'decline_extend') {
      await Ride.updateOne({ _id: ride._id }, { $unset: { pendingExtension: 1 } })
      return withCors({ success: true, declined: true })
    } else if (action === 'end') {
      if (!ride.rentalStartedAt) return withCors({ error: 'Rental not started' }, 409)
      const f = validFix(b)
      if (f && !ride.isWaiting) {
        const km = plausibleKm(ride, f.lat, f.lng, now.getTime())
        if (km != null && km > 0) ride.actualKm = +(ride.actualKm + km).toFixed(2)
      }
      ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)

      const ex = rentalExtras(ride)
      ride.extraHoursCharge = ex.extraHoursCharge
      ride.extraKmCharge = ex.extraKmCharge
      const base = ride.fare || 0
      ride.finalFare = Math.round(base + ride.extraHoursCharge + ride.extraKmCharge + (ride.nightChargeRental || 0))
      ride.totalFare = ride.finalFare + (ride.tip || 0)
      ride.rentalPhase = 'completed'
      ride.rentalEndedAt = now
      ride.pendingExtension = undefined
      pendingExtension = null
      // Settlement happens in /rides/{id}/complete, never here.
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    }

    await ride.save()
    return respond(ride, alreadyStarted, ignoredPing, pendingExtension)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

function respond(ride: any, alreadyStarted: boolean, ignoredPing: boolean, pendingExtension: any) {
  const live = rentalExtras(ride)
  return withCors({
    success: true,
    alreadyStarted,
    ...(ignoredPing ? { ignoredPing: true } : {}),
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
    },
  })
}
