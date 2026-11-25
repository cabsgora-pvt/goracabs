export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth, requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { hireExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'
import { cashDueFor } from '@/lib/settlement'
import {
  parseExtraHours, priceHireExtension, requestExtension, confirmExtension,
  livePendingExtension, MAX_EXTEND_HOURS,
} from '@/lib/ride-extension'

export async function OPTIONS() { return corsOptions() }

const DRIVER_ACTIONS = new Set(['start', 'ping', 'extend', 'end'])
const RIDER_ACTIONS = new Set(['confirm_extend', 'decline_extend'])
const OPEN = { status: 'ongoing', hirePhase: { $ne: 'completed' } }

// POST /api/rides/{id}/hire  body.action:
//  driver (the ASSIGNED driver, ride status 'ongoing'):
//  'start'  → mark hireStartedAt, phase ongoing (idempotent)
//  'ping'   → live actualHours (flip to overtime over booked hours)
//  'extend' { extraHours } → ASK the rider for 1..12 more hours, priced at
//            hirePerHour × hours → pendingExtension (nothing changes yet).
//            409 EXTENSION_PENDING while one is live, EXTENSION_LIMIT after 3.
//  'end'    → finalize: extra hours × perHour overtime, hireFinalFare. A retry
//            after the end returns the same bill (200 { alreadyEnded }).
//  rider (the ride's rider):
//  'confirm_extend' { requestedAt, amount } → hireTotalHours += hours, fare += amount
//  'decline_extend' → drop the request
// The rider can no longer start, end or extend a hire directly.
//
// 'end' does NOT complete the ride: price here, collect in the app, settle in
// /rides/{id}/complete. It returns `amountDue` / `cashToCollect`, what the
// driver must take. Every write is atomic on status 'ongoing' + hirePhase !=
// 'completed', so a ping racing 'end' cannot alter the bill.

/** Cash the driver collects for this ride (lib/settlement cashDueFor; 0 unless it is a cash ride). */
function cashToCollect(ride: any): number {
  return ride.paymentMode === 'cash' ? cashDueFor(ride) : 0
}

const hoursSince = (t: any, now: Date) => +(((now.getTime() - new Date(t).getTime()) / 3600000)).toFixed(2)

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
    if (ride.service !== 'hire_driver') return withCors({ error: 'Not a hire ride' }, 400)

    if (DRIVER_ACTIONS.has(action)) {
      const d = requireDriverAuth(req) as any
      if (!d?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.driverId || String(ride.driverId) !== String(d.id)) return withCors({ error: 'Not your ride' }, 403)
    } else {
      const u = requireRider(req) as any
      if (!u?.id) return withCors({ error: 'Unauthorized' }, 401)
      if (!ride.riderId || String(ride.riderId) !== String(u.id)) return withCors({ error: 'Not your ride' }, 403)
    }

    // ── Once billed, the hire is closed for changes; a repeated 'end' gets the bill ──
    if (ride.hirePhase === 'completed' || ride.status === 'completed') {
      if (action === 'end') return ended(ride)
      return withCors({ error: 'Hire already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)
    if (ride.status !== 'ongoing') {
      return withCors({ error: `Not allowed while the ride is ${ride.status}`, code: 'NOT_ONGOING' }, 409)
    }

    const now = new Date()
    const reload = async () => (await Ride.findById(ride._id).lean()) as any

    if (action === 'start') {
      const res = await Ride.updateOne({ _id: ride._id, ...OPEN, hireStartedAt: null },
        { $set: { hireStartedAt: now, hirePhase: 'ongoing', hireActualHours: 0 } })
      return respond(await reload(), !res.modifiedCount, null)
    }

    if (action === 'ping') {
      const set: any = {}
      if (ride.hireStartedAt) set.hireActualHours = hoursSince(ride.hireStartedAt, now)
      const hours = set.hireActualHours ?? ride.hireActualHours ?? 0
      if (hours > (ride.hireTotalHours || 0) && ride.hirePhase === 'ongoing') set.hirePhase = 'overtime'
      if (Object.keys(set).length) {
        const res = await Ride.updateOne({ _id: ride._id, ...OPEN }, { $set: set })
        if (!res.matchedCount) return withCors({ error: 'Hire already completed' }, 409)
      }
      return respond(await reload(), false, null)
    }

    if (action === 'extend') {
      const extra = parseExtraHours(b.extraHours)
      if (extra == null) return withCors({ error: `extraHours must be a whole number between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      const price = priceHireExtension(ride, extra)
      const r = await requestExtension(ride, 'hire', extra, price.amount)
      if (!r.ok) return withCors({ error: r.error, code: r.code, ...(r.pendingExtension ? { pendingExtension: r.pendingExtension } : {}) }, r.status)
      return withCors({ success: true, awaitingRiderConfirmation: true, pendingExtension: r.pendingExtension, basis: price.basis })
    }

    if (action === 'confirm_extend') {
      const r = await confirmExtension(ride._id, 'hire', { requestedAt: b.requestedAt, amount: b.amount },
        (p) => ({ inc: { hireTotalHours: p.hours } }))
      if (!r.ok) return withCors({ error: r.error, code: r.code, ...(r.pendingExtension ? { pendingExtension: r.pendingExtension } : {}) }, r.status)
      const done: any = r.ride
      if (done.hirePhase === 'overtime' && done.hireActualHours <= done.hireTotalHours) {
        await Ride.updateOne({ _id: done._id, hirePhase: 'overtime' }, { $set: { hirePhase: 'ongoing' } })
        done.hirePhase = 'ongoing'
      }
      return respond(done, false, null)
    }

    if (action === 'decline_extend') {
      await Ride.updateOne({ _id: ride._id }, { $unset: { pendingExtension: 1 } })
      return withCors({ success: true, declined: true })
    }

    // ── 'end' ──
    const hireActualHours = ride.hireStartedAt ? hoursSince(ride.hireStartedAt, now) : (ride.hireActualHours || 0)
    const ex = hireExtras({ ...ride, hireActualHours })
    const hireFinalFare = Math.round((ride.fare || 0) + ex.extraCharge)
    const set: any = {
      hireActualHours, hireExtraHours: ex.extraHours, hireExtraCharge: ex.extraCharge,
      hireFinalFare, totalFare: hireFinalFare + (ride.tip || 0),
      hirePhase: 'completed', hireEndAt: now,
    }
    if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
      set.awaitingPayment = true
      set.paymentStatus = 'pending'
    }
    const done: any = await Ride.findOneAndUpdate({ _id: ride._id, ...OPEN }, { $set: set, $unset: { pendingExtension: 1 } }, { new: true }).lean()
    if (!done) {
      const cur = await reload()
      if (cur && (cur.hirePhase === 'completed' || cur.status === 'completed')) return ended(cur)
      return withCors({ error: `Not allowed while the ride is ${cur?.status}`, code: 'NOT_ONGOING' }, 409)
    }
    return ended(done, false)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

function ended(ride: any, already = true) {
  return respond(ride, false, null, { ...(already ? { alreadyEnded: true } : {}), cashToCollect: cashToCollect(ride) })
}

function respond(ride: any, alreadyStarted: boolean, pendingExtension: any, extra: Record<string, any> = {}) {
  // Cash-in-hand at the end of the job — the final fare, overtime included.
  const amountDue = ride.hirePhase === 'completed' && ride.paymentMode === 'cash' ? (ride.totalFare || 0) : 0
  const liveHire = hireExtras(ride)
  return withCors({
    success: true,
    amountDue,
    alreadyStarted,
    ...extra,
    hire: {
      elapsedSec: secondsSince(ride.hireStartedAt),
      liveExtraHours: liveHire.extraHours,
      liveExtraCharge: Math.round(liveHire.extraCharge),
      phase: ride.hirePhase, actualHours: ride.hireActualHours, totalHours: ride.hireTotalHours,
      extraHours: ride.hireExtraHours, extraCharge: ride.hireExtraCharge,
      finalFare: ride.hireFinalFare, status: ride.status, hireStartedAt: ride.hireStartedAt,
      baseFare: ride.fare || 0,
      pendingExtension: pendingExtension ?? livePendingExtension(ride),
    },
  })
}
