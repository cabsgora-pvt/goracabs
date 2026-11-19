export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { otp } → start ride if OTP matches
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { otp } = await req.json()
    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    // Only the assigned driver, and only before the trip has started.
    if (!ride.driverId || String(ride.driverId) !== String(payload.id)) {
      return withCors({ error: 'Not your ride' }, 403)
    }
    // A repeat of a start that went through but whose answer was lost.
    if (ride.status === 'ongoing' && String(otp) === String(ride.otp)) return withCors({ success: true, repeated: true })
    if (!['accepted', 'arrived'].includes(ride.status)) {
      return withCors({ error: `Ride cannot be started (status: ${ride.status})` }, 400)
    }

    if (String(otp) !== String(ride.otp)) return withCors({ error: 'Invalid OTP' }, 400)

    ride.status = 'ongoing'
    ride.startedAt = new Date()
    // outstationPhase only ever moved on a round trip's driver-reported legs,
    // so every outstation ride read "pickup_pending" until — and after — the end.
    if (ride.service === 'outstation') ride.outstationPhase = 'enroute'
    await ride.save()

    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
