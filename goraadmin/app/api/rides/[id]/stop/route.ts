export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import VehicleType from '@/models/VehicleType'
import { withCors, corsOptions } from '@/lib/cors'
import { requireDriverAuth } from '@/lib/auth'

export async function OPTIONS() { return corsOptions() }

const FREE_WAIT_MIN = 5 // free waiting minutes per stop

// POST /api/rides/{id}/stop  body.action:
//  'reached' { index }  → driver reached stop[index]; start its wait timer
//  'resume'  { index }  → driver resumes; add wait charge for that stop; advance currentStopIndex
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const d = requireDriverAuth(req) as any
    if (!d?.id) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const b = await req.json().catch(() => ({}))
    if (!['reached', 'resume'].includes(b?.action)) return withCors({ error: 'Unknown action' }, 400)
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    // The assigned driver only, while the trip is under way.
    if (!ride.driverId || String(ride.driverId) !== String(d.id)) return withCors({ error: 'Not your ride' }, 403)
    if (ride.status !== 'ongoing') return withCors({ error: `Not allowed while the ride is ${ride.status}`, code: 'NOT_ONGOING' }, 409)
    if (!ride.stops || !ride.stops.length) return withCors({ error: 'No stops on this ride' }, 400)

    const idx = b.index ?? ride.currentStopIndex ?? 0
    if (!Number.isInteger(idx) || idx < 0 || idx >= ride.stops.length) {
      return withCors({ error: 'Invalid stop index' }, 400)
    }
    const stop = ride.stops[idx]
    // Each stop is reached once and resumed once.
    if (stop.done) return withCors({ error: 'This stop is already done', code: 'STOP_DONE' }, 409)

    const now = new Date()

    if (b.action === 'reached') {
      if (stop.reachedAt) return withCors({ error: 'Already at this stop', code: 'STOP_ALREADY_REACHED' }, 409)
      stop.reachedAt = now
      stop.waitStartedAt = now
      ride.isWaitingAtStop = true
      ride.currentStopIndex = idx
    } else {
      if (!stop.reachedAt) return withCors({ error: 'Mark the stop reached first', code: 'STOP_NOT_REACHED' }, 409)
      // Compute waited minutes beyond free wait → charge
      if (stop.waitStartedAt) {
        const mins = (now.getTime() - new Date(stop.waitStartedAt).getTime()) / 60000
        stop.waitMinutes = +mins.toFixed(1)
        const billable = Math.max(0, Math.ceil(mins - FREE_WAIT_MIN))
        // waiting rate from the vehicle type
        let rate = 1
        const vt: any = await VehicleType.findOne({ name: ride.vehicleType }).select('waitingCharge').lean()
        if (vt?.waitingCharge != null) rate = vt.waitingCharge
        ride.waitingChargeTotal = +((ride.waitingChargeTotal || 0) + billable * rate).toFixed(2)
      }
      stop.done = true
      ride.isWaitingAtStop = false
      ride.currentStopIndex = idx + 1
    }

    ride.markModified('stops')
    // Saved only if this stop is still in the state read above, so a double
    // tap cannot add the wait charge twice.
    const guard: any = { _id: ride._id, status: 'ongoing', [`stops.${idx}.done`]: { $ne: true } }
    if (b.action === 'reached') guard[`stops.${idx}.reachedAt`] = null
    const res = await Ride.updateOne(guard, { $set: {
      stops: ride.stops.map((s: any) => (s?.toObject ? s.toObject() : s)), isWaitingAtStop: ride.isWaitingAtStop,
      currentStopIndex: ride.currentStopIndex, waitingChargeTotal: ride.waitingChargeTotal,
    } })
    if (!res.matchedCount) return withCors({ error: 'This stop changed — refresh and try again', code: 'STOP_CHANGED' }, 409)
    return withCors({
      success: true,
      currentStopIndex: ride.currentStopIndex,
      isWaitingAtStop: ride.isWaitingAtStop,
      waitingChargeTotal: ride.waitingChargeTotal,
      freeWaitMin: FREE_WAIT_MIN,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
