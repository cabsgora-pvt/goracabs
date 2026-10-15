export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { requireAuth, requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { rentalExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/rental  body.action:
//  'start'    { lat, lng }        driver → mark start, set rentalStartedAt
//  'ping'     { lat, lng }        driver → accumulate actualKm + actualHours
//  'wait'     { isWaiting }       driver → toggle halt
//  'addStop'  { address,lat,lng } rider  → append a destination
//  'extend'   { extraHours }      driver → increase packageHours (+ included km)
//  'end'      { lat, lng }        driver → finalize extras + finalFare
//
// AUTH: this route previously had NONE — no requireAuth, no requireDriverAuth,
// no ownership check. Anyone who knew a rideId could end a live rental, extend
// it, or spam pings to inflate the odometer. Actions are now split by role and
// the caller must be the ride's own driver/rider.

const DRIVER_ACTIONS = new Set(['start', 'ping', 'wait', 'extend', 'end'])
const RIDER_ACTIONS = new Set(['addStop'])
const MAX_EXTEND_HOURS = 12

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json()
    const action = String(b.action || '')

    if (!DRIVER_ACTIONS.has(action) && !RIDER_ACTIONS.has(action)) {
      return withCors({ error: 'Unknown action' }, 400)
    }

    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.service !== 'rental') return withCors({ error: 'Not a rental ride' }, 400)

    // ── Authorise: the assigned driver for driver actions, the rider for theirs
    if (DRIVER_ACTIONS.has(action)) {
      const d = requireDriverAuth(req) as any
      if (!d?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.driverId || String(ride.driverId) !== String(d.id)) {
        return withCors({ error: 'Not your ride' }, 403)
      }
    } else {
      const u = requireAuth(req) as any
      if (!u?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.riderId || String(ride.riderId) !== String(u.id)) {
        return withCors({ error: 'Not your ride' }, 403)
      }
    }

    // ── Idempotency: once billed, the rental is closed for changes ──
    // Without this, calling 'end' twice recomputed actualHours against a fresh
    // `now` each time, so finalFare grew on every extra call.
    if (ride.rentalPhase === 'completed' || ride.status === 'completed') {
      return withCors({ error: 'Rental already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)

    const now = new Date()

    // A "waiting" rental should be parked. If the vehicle has clearly moved on
    // from where it halted, waiting is auto-released and the odometer resumes —
    // otherwise a driver could hold the toggle down and drive the whole rental
    // for free, since km never accrue while waiting.
    const WAIT_DRIFT_KM = 0.5

    // 'start' is idempotent. A reopened rental screen calls it again, and it
    // used to answer 409 with no rental in the body — so the screen fell back to
    // the phone's "now" and showed a clock reading 0:00 on a rental hours in.
    // A repeat start changes nothing and returns the rental as it stands.
    let alreadyStarted = false
    if (action === 'start') {
      if (ride.rentalStartedAt) {
        alreadyStarted = true
      } else {
        ride.rentalStartedAt = now
        ride.rentalPhase = 'ongoing'
        ride.rentalLastLat = b.lat ?? ride.pickupLat
        ride.rentalLastLng = b.lng ?? ride.pickupLng
        ride.actualKm = 0
        ride.actualHours = 0
      }
    } else if (action === 'ping') {
      // Auto-release a "wait" the vehicle has driven away from.
      if (ride.isWaiting && b.lat != null && b.lng != null && ride.rentalLastLat != null) {
        const drift = distanceKm(
          { lat: ride.rentalLastLat, lng: ride.rentalLastLng },
          { lat: b.lat, lng: b.lng },
        )
        if (drift > WAIT_DRIFT_KM) {
          ride.isWaiting = false
          ride.actualKm = +(ride.actualKm + drift).toFixed(2)
          ride.rentalLastLat = b.lat
          ride.rentalLastLng = b.lng
          ride.rentalPhase = ride.actualHours > ride.packageHours ? 'extra_time' : 'ongoing'
        }
      }
      // Accumulate distance from last point (skip while waiting)
      if (!ride.isWaiting && b.lat != null && b.lng != null && ride.rentalLastLat != null) {
        const d = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat: b.lat, lng: b.lng })
        if (d > 0.02) { // ignore GPS jitter < 20m
          ride.actualKm = +(ride.actualKm + d).toFixed(2)
          ride.rentalLastLat = b.lat
          ride.rentalLastLng = b.lng
        }
      }
      if (ride.rentalStartedAt) {
        ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      if (ride.actualHours > ride.packageHours || ride.actualKm > ride.packageKm) {
        if (ride.rentalPhase === 'ongoing') ride.rentalPhase = 'extra_time'
      }
      // NOTE: extraHoursCharge / extraKmCharge are deliberately NOT written
      // here. They are the billed figures and belong to 'end' alone. The live
      // projection below is returned but never persisted, so nothing can settle
      // against a mid-ride estimate.
    } else if (action === 'wait') {
      ride.isWaiting = !!b.isWaiting
      ride.rentalPhase = b.isWaiting ? 'paused' : (ride.actualHours > ride.packageHours ? 'extra_time' : 'ongoing')
      if (b.lat != null) { ride.rentalLastLat = b.lat; ride.rentalLastLng = b.lng } // reset anchor on resume
    } else if (action === 'addStop') {
      if (!b.address || b.lat == null || b.lng == null) {
        return withCors({ error: 'address, lat and lng required' }, 400)
      }
      ride.rentalStops = ride.rentalStops || []
      ride.rentalStops.push({ address: String(b.address), lat: b.lat, lng: b.lng, at: now })
    } else if (action === 'extend') {
      const extra = Number(b.extraHours)
      // Was unvalidated: a negative value shrank the package and instantly
      // manufactured extra-hour charges.
      if (!Number.isFinite(extra) || extra <= 0 || extra > MAX_EXTEND_HOURS) {
        return withCors({ error: `extraHours must be between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      }
      const oldHours = ride.packageHours || 0
      // Scale included km off the ORIGINAL rate. The previous version divided by
      // the already-updated hours, so packageKm came out identical every time
      // and the rider paid extra-km for the hours they had just bought.
      const perHrKm = oldHours > 0 ? (ride.packageKm || 0) / oldHours : 0
      ride.packageHours = oldHours + extra
      ride.packageKm = Math.round(perHrKm * ride.packageHours)
      if (ride.actualHours <= ride.packageHours && ride.actualKm <= ride.packageKm) {
        ride.rentalPhase = 'ongoing'
      }
    } else if (action === 'end') {
      if (!ride.rentalStartedAt) return withCors({ error: 'Rental not started' }, 409)
      if (b.lat != null && ride.rentalLastLat != null) {
        const d = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat: b.lat, lng: b.lng })
        if (d > 0.02) ride.actualKm = +(ride.actualKm + d).toFixed(2)
      }
      ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)

      // Shared formula (lib/ride-extras.ts), proven identical to the inline
      // version it replaces, so the bill and the rider's live total agree.
      const ex = rentalExtras(ride)
      ride.extraHoursCharge = ex.extraHoursCharge
      ride.extraKmCharge = ex.extraKmCharge
      const base = ride.fare || 0
      ride.finalFare = Math.round(base + ride.extraHoursCharge + ride.extraKmCharge + (ride.nightChargeRental || 0))
      // totalFare drives what the rider is asked to pay — extras included.
      ride.totalFare = ride.finalFare + (ride.tip || 0)
      ride.rentalPhase = 'completed'
      ride.rentalEndedAt = now

      // The ride is NOT marked completed here. Settlement (commission split,
      // driver wallet, Transaction row) happens in /rides/{id}/complete, which
      // the driver app calls after collecting cash and the rider app calls
      // after paying online. Completing inline was why rentals never produced
      // any commission at all.
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    }

    await ride.save()

    // Same formula 'end' uses, so the running total and the final bill cannot
    // drift apart and surprise the rider.
    const live = rentalExtras(ride)
    const liveExtraHrs = live.extraHours
    const liveExtraKms = live.extraKm
    const liveExtraCharge = Math.round(live.total)

    return withCors({
      success: true,
      alreadyStarted,
      rental: {
        // Server-clock seconds since the rental began, so the driver's clock
        // does not inherit the phone's time error. Null before the start.
        elapsedSec: secondsSince(ride.rentalStartedAt),
        // Live, non-binding projection of what the extras have reached so far.
        // The driver could see the phase flip to 'extra_time' but had no idea
        // how much money was accruing — the charges were only ever computed at
        // 'end', by which point the rider is already being handed a bill.
        liveExtraHours: liveExtraHrs,
        liveExtraKm: liveExtraKms,
        liveExtraCharge: liveExtraCharge,
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
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
