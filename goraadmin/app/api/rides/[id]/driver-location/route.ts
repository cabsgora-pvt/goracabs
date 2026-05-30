export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/{id}/driver-location
// Returns the assigned driver's current lat/lng/heading + a freshness timestamp.
// Polled by the rider's map every 5s while the ride is accepted/arrived/ongoing.
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('driverId status').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (!ride.driverId) return withCors({ driver: null, status: ride.status })

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
