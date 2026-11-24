export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth, requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { hireExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'
import {
  parseExtraHours, priceHireExtension, requestExtension, confirmExtension,
  livePendingExtension, MAX_EXTEND_HOURS,
} from '@/lib/ride-extension'

export async function OPTIONS() { return corsOptions() }

const DRIVER_ACTIONS = new Set(['start', 'ping', 'extend', 'end'])
const RIDER_ACTIONS = new Set(['confirm_extend', 'decline_extend'])

// POST /api/rides/{id}/hire  body.action:
//  driver (the ASSIGNED driver, ride status 'ongoing'):
//  'start'  → mark hireStartedAt, phase ongoing (idempotent)
//  'ping'   → live actualHours (flip to overtime over booked hours)
//  'extend' { extraHours } → ASK the rider for 1..12 more hours, priced at
//            hirePerHour × hours → pendingExtension (nothing changes yet)
//  'end'    → finalize: extra hours × perHour overtime, hireFinalFare
//  rider (the ride's rider):
//  'confirm_extend' → hireTotalHours += hours, fare += amount
//  'decline_extend' → drop the request
// The rider can no longer start, end or extend a hire directly.
//
// 'end' does NOT complete the ride: price here, collect in the app, settle in
// /rides/{id}/complete. It returns `amountDue`, what the driver must take.
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

    // ── Once billed, the hire is closed for changes ──
    if (ride.hirePhase === 'completed' || ride.status === 'completed') {
      return withCors({ error: 'Hire already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)
    if (ride.status !== 'ongoing') {
      return withCors({ error: `Not allowed while the ride is ${ride.status}`, code: 'NOT_ONGOING' }, 409)
    }

    const now = new Date()
    let alreadyStarted = false
    let pendingExtension: any = livePendingExtension(ride)

    if (action === 'start') {
      if (ride.hireStartedAt) {
        alreadyStarted = true
      } else {
        ride.hireStartedAt = now
        ride.hirePhase = 'ongoing'
        ride.hireActualHours = 0
      }
    } else if (action === 'ping') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      if (ride.hireActualHours > ride.hireTotalHours && ride.hirePhase === 'ongoing') ride.hirePhase = 'overtime'
    } else if (action === 'extend') {
      const extra = parseExtraHours(b.extraHours)
      if (extra == null) return withCors({ error: `extraHours must be a whole number between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      const price = priceHireExtension(ride, extra)
      pendingExtension = await requestExtension(ride, 'hire', extra, price.amount)
      return withCors({ success: true, awaitingRiderConfirmation: true, pendingExtension, basis: price.basis })
    } else if (action === 'confirm_extend') {
      const done: any = await confirmExtension(ride._id, 'hire', (p) => ({ inc: { hireTotalHours: p.hours } }))
      if (!done) return withCors({ error: 'No extension is waiting for your confirmation', code: 'NO_PENDING_EXTENSION' }, 409)
      if (done.hirePhase === 'overtime' && done.hireActualHours <= done.hireTotalHours) {
        await Ride.updateOne({ _id: done._id, hirePhase: 'overtime' }, { $set: { hirePhase: 'ongoing' } })
        done.hirePhase = 'ongoing'
      }
      return respond(done, false, null)
    } else if (action === 'decline_extend') {
      await Ride.updateOne({ _id: ride._id }, { $unset: { pendingExtension: 1 } })
      return withCors({ success: true, declined: true })
    } else if (action === 'end') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      const ex = hireExtras(ride)
      ride.hireExtraHours = ex.extraHours
      ride.hireExtraCharge = ex.extraCharge
      const base = ride.fare || 0
      ride.hireFinalFare = Math.round(base + ride.hireExtraCharge)
      ride.totalFare = ride.hireFinalFare + (ride.tip || 0)
      ride.hirePhase = 'completed'
      ride.hireEndAt = now
      ride.pendingExtension = undefined
      pendingExtension = null
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    }

    await ride.save()
    return respond(ride, alreadyStarted, pendingExtension)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

function respond(ride: any, alreadyStarted: boolean, pendingExtension: any) {
  // Cash-in-hand at the end of the job — the final fare, overtime included.
  const amountDue = ride.hirePhase === 'completed' && ride.paymentMode === 'cash' ? (ride.totalFare || 0) : 0
  const liveHire = hireExtras(ride)
  return withCors({
    success: true,
    amountDue,
    alreadyStarted,
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
