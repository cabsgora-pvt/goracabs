export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { rideActor } from '@/lib/ride-view'

const PHASES = ['pickup_pending', 'driver_arriving', 'picked_up', 'enroute', 'at_destination', 'returning', 'completed']

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/phase  body: { phase: 'at_destination' | 'returning' | ..., actualDistance?, confirmNightHalt? }
// Lightweight endpoint driver + user apps both call to advance outstation flow.
//
// It no longer sets tollCharge. That field is now the sum of the itemised
// `tolls`, maintained only by /rides/{id}/toll; accepting a bare number here —
// from the rider as well as the driver — would let either side overwrite the
// total without an entry to show for it. Nothing ever sent it.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()

    // Only this ride's rider, its assigned driver, or an admin may act on it.
    const _r: any = await Ride.findById(params.id).select('riderId driverId status').lean()
    if (!_r) return withCors({ error: 'Ride not found' }, 404)
    const who = rideActor(req, _r)
    if (!('actor' in who)) return withCors({ error: who.error, code: who.code }, who.status)
    if (['completed', 'cancelled'].includes(_r.status)) return withCors({ error: `Ride is ${_r.status}` }, 409)

    const body = await req.json().catch(() => ({}))
    const update: any = {}
    if (body.phase != null) {
      if (!PHASES.includes(body.phase)) return withCors({ error: 'Unknown phase' }, 400)
      update.outstationPhase = body.phase
    }
    // Odometer figure: the driver's, never the rider's.
    if (typeof body.actualDistance === 'number' && who.actor.role !== 'rider') {
      if (!Number.isFinite(body.actualDistance) || body.actualDistance < 0 || body.actualDistance > 5000) {
        return withCors({ error: 'Invalid actualDistance' }, 400)
      }
      update.actualDistance = body.actualDistance
    }
    if (body.confirmNightHalt) {
      update.nightHaltConfirmed = true
      update.nightHaltConfirmedAt = new Date()
    }
    if (!Object.keys(update).length) return withCors({ success: true })
    const ride: any = await Ride.findByIdAndUpdate(params.id, { $set: update }, { new: true })
      .select(Object.keys(update).join(' ')).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    // Only the fields this call changed — never the whole ride (it used to
    // return the full document, OTPs included, to the driver).
    const { _id, ...changed } = ride
    return withCors({ success: true, ride: { id: String(_id), ...changed } })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
