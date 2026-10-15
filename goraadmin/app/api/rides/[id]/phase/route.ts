export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { guardRideActor } from '@/lib/admin-guard'

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
    {
      const _r: any = await Ride.findById(params.id).select('riderId driverId').lean()
      if (!_r) return withCors({ error: 'Ride not found' }, 404)
      const _denied = guardRideActor(req, _r)
      if (_denied) return withCors(await _denied.json(), _denied.status)
    }
    const body = await req.json()
    const update: any = {}
    if (body.phase) update.outstationPhase = body.phase
    if (typeof body.actualDistance === 'number') update.actualDistance = body.actualDistance
    if (body.confirmNightHalt) {
      update.nightHaltConfirmed = true
      update.nightHaltConfirmedAt = new Date()
    }
    const ride = await Ride.findByIdAndUpdate(params.id, update, { new: true }).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ success: true, ride })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
