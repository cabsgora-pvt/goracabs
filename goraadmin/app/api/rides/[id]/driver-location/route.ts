export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'
import { rideActor, ACTIVE_STATUSES } from '@/lib/ride-view'
import { requireRider } from '@/lib/auth'
import User from '@/models/User'
import { phoneLast10 } from '@/models/Ride'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/{id}/driver-location
// The assigned driver's current lat/lng/heading + a freshness timestamp.
// Polled by the rider's map every 5s while the ride is accepted/arrived/ongoing.
// Only the ride's rider, its assigned driver or an admin may read it, and the
// position is only given while the ride is accepted / arrived / ongoing —
// before and after that `driver` is null. (It used to need no auth at all.)
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('riderId driverId status service receiverPhoneNorm').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const who = rideActor(req, ride)
    if (!('actor' in who)) {
      // The parcel's RECEIVER (a rider whose phone is the receiverPhone) may
      // follow the courier too — the same window as the sender.
      const u = requireRider(req) as any
      let receiver = false
      if (u?.id && ride.service === 'delivery' && ride.receiverPhoneNorm) {
        const me: any = await User.findById(u.id).select('phone').lean()
        receiver = !!me && phoneLast10(me.phone) === ride.receiverPhoneNorm
      }
      if (!receiver) return withCors({ error: who.error, code: who.code }, who.status)
    }
    if (!ride.driverId || !ACTIVE_STATUSES.includes(ride.status)) return withCors({ driver: null, status: ride.status })

    const driver: any = await Driver.findById(ride.driverId)
      .select('currentLat currentLng currentHeading locationUpdatedAt')
      .lean()

    return withCors({
      status: ride.status,
      driver: driver ? {
        lat: driver.currentLat ?? null,
        lng: driver.currentLng ?? null,
        heading: driver.currentHeading ?? 0,
        updatedAt: driver.locationUpdatedAt ?? null,
      } : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
