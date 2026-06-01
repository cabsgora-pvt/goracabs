export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/phase  body: { phase: 'at_destination' | 'returning' | ..., actualDistance?, tollCharge?, confirmNightHalt? }
// Lightweight endpoint driver + user apps both call to advance outstation flow.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const update: any = {}
    if (body.phase) update.outstationPhase = body.phase
    if (typeof body.actualDistance === 'number') update.actualDistance = body.actualDistance
    if (typeof body.tollCharge === 'number') update.tollCharge = body.tollCharge
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
