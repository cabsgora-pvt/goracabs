export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { guardRideActor } from '@/lib/admin-guard'
import { hireExtras } from '@/lib/ride-extras'
import { secondsSince } from '@/lib/ride-phase'

export async function OPTIONS() { return corsOptions() }

const HIRE_ACTIONS = new Set(['start', 'ping', 'extend', 'end'])
const MAX_EXTEND_HOURS = 12

// POST /api/rides/{id}/hire  body.action:
//  'start'  → mark hireStartedAt, phase ongoing
//  'ping'   → live actualHours (flip to overtime over booked hours)
//  'extend' { extraHours } → bump booked hours
//  'end'    → finalize: extra hours × perHour overtime, hireFinalFare
//
// 'end' does NOT complete the ride. It used to set status = 'completed' inline,
// which skipped /rides/{id}/complete — so a hire produced no commission, no
// Transaction and no wallet movement, exactly as rentals and deliveries did
// before they were fixed. Price here, collect in the app, settle in /complete.
//
// It returns `amountDue`, which is what the driver must actually take: the
// final fare INCLUDING overtime. The app used to collect the booked fare before
// calling this, so every overtime hour was billed on screen and then written off.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()

    // Only this ride's rider, its assigned driver, or an admin may act on it.
    {
      const _r: any = await Ride.findById(params.id).select('riderId driverId').lean()
      if (!_r) return withCors({ error: 'Ride not found' }, 404)
      const _denied = guardRideActor(req, _r)
      if (_denied) return withCors(await _denied.json(), _denied.status)
    }
    const b = await req.json()
    if (!HIRE_ACTIONS.has(String(b.action || ''))) {
      return withCors({ error: 'Unknown action' }, 400)
    }
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.service !== 'hire_driver') return withCors({ error: 'Not a hire ride' }, 400)

    // ── Once billed, the hire is closed for changes ──
    // The rental route has had this guard; hire did not. A second 'end' re-ran
    // the overtime sum against a later `now` and overwrote the bill, and a late
    // 'extend' could rewrite booked hours on a job already settled.
    if (ride.hirePhase === 'completed' || ride.status === 'completed') {
      return withCors({ error: 'Hire already completed' }, 409)
    }
    if (ride.status === 'cancelled') return withCors({ error: 'Ride cancelled' }, 409)

    const now = new Date()

    // 'start' is idempotent. It used to reset hireStartedAt to now and the hours
    // worked to 0 on EVERY call — and the driver app calls it whenever the hire
    // screen opens, including when a driver reopens the app mid-job. Each
    // reopen silently wiped the hours worked so far, and with them the overtime
    // the customer owed and the driver had earned.
    let alreadyStarted = false
    if (b.action === 'start') {
      if (ride.hireStartedAt) {
        alreadyStarted = true
      } else {
        ride.hireStartedAt = now
        ride.hirePhase = 'ongoing'
        ride.hireActualHours = 0
      }
    } else if (b.action === 'ping') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      if (ride.hireActualHours > ride.hireTotalHours && ride.hirePhase === 'ongoing') ride.hirePhase = 'overtime'
    } else if (b.action === 'extend') {
      // Unvalidated, a negative value shrank the booking and turned hours
      // already worked into instant overtime. Same bounds as rental.
      const extra = Number(b.extraHours)
      if (!Number.isFinite(extra) || extra <= 0 || extra > MAX_EXTEND_HOURS) {
        return withCors({ error: `extraHours must be between 1 and ${MAX_EXTEND_HOURS}` }, 400)
      }
      ride.hireTotalHours = (ride.hireTotalHours || 0) + extra
      if (ride.hireActualHours <= ride.hireTotalHours) ride.hirePhase = 'ongoing'
    } else if (b.action === 'end') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      // Shared formula (lib/ride-extras.ts), proven identical to the inline
      // version it replaces.
      const ex = hireExtras(ride)
      ride.hireExtraHours = ex.extraHours
      ride.hireExtraCharge = ex.extraCharge
      const base = ride.fare || 0
      ride.hireFinalFare = Math.round(base + ride.hireExtraCharge)
      ride.totalFare = ride.hireFinalFare + (ride.tip || 0)
      ride.hirePhase = 'completed'
      ride.hireEndAt = now
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    }

    await ride.save()

    // Cash-in-hand at the end of the job — the final fare, overtime included.
    const amountDue = ride.hirePhase === 'completed' && ride.paymentMode === 'cash'
      ? (ride.totalFare || 0)
      : 0

    // Live, non-binding overtime projection, using the same formula as 'end' so
    // the running total and the closing bill cannot drift apart. Never written
    // to the ride — hireExtraCharge stays the billed figure, set only at 'end'.
    const liveHire = hireExtras(ride)
    const liveExtraHours = liveHire.extraHours
    const liveExtraCharge = Math.round(liveHire.extraCharge)

    return withCors({
      success: true,
      amountDue,
      alreadyStarted,
      hire: {
        // Server-clock seconds since the hire began, so the driver's clock does
        // not inherit the phone's time error. Null before the start.
        elapsedSec: secondsSince(ride.hireStartedAt),
        liveExtraHours,
        liveExtraCharge,
        phase: ride.hirePhase, actualHours: ride.hireActualHours, totalHours: ride.hireTotalHours,
        extraHours: ride.hireExtraHours, extraCharge: ride.hireExtraCharge,
        finalFare: ride.hireFinalFare, status: ride.status, hireStartedAt: ride.hireStartedAt,
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
