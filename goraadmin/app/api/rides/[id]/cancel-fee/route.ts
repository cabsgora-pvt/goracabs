export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import ServiceConfig from '@/models/ServiceConfig'
import { withCors, corsOptions } from '@/lib/cors'
import { guardRideActor } from '@/lib/admin-guard'

export async function OPTIONS() { return corsOptions() }

// GET → what cancelling THIS ride right now would cost the rider, using the
// exact same rule POST /cancel applies (see that file) — so the rider sees it
// before they commit to cancelling, not only after in the response.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('riderId driverId service status').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const denied = guardRideActor(req, ride)
    if (denied) return withCors(await denied.json(), denied.status)

    const driverWasCommitted = ['accepted', 'arrived'].includes(ride.status)
    let fee = 0
    if (driverWasCommitted) {
      const cfg: any = await ServiceConfig.findOne({ service: ride.service }).lean().catch(() => null)
      fee = Math.max(0, Number(cfg?.cancellationFee) || 0)
    }
    return withCors({ fee, appliesNow: driverWasCommitted && fee > 0 })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
