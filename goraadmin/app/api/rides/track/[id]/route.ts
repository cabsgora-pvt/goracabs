export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/track/{id}
// Public endpoint (no auth) for share link. Returns only safe fields:
//   - rider name, pickup + drop addresses + coords, route polyline, status
//   - driver name (no phone, no plate), live lat/lng/heading
// Family members open https://goracabs.com/track/{id} to see live map.
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id)
      .select('riderName pickupAddress dropAddress pickupLat pickupLng dropLat dropLng routePolyline status driverId driverName')
      .lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    let driver: any = null
    if (ride.driverId) {
      const d: any = await Driver.findById(ride.driverId)
        .select('currentLat currentLng currentHeading locationUpdatedAt vehicleModel')
        .lean()
      if (d) driver = {
        name: ride.driverName,
        vehicleModel: d.vehicleModel || '',
        lat: d.currentLat ?? null,
        lng: d.currentLng ?? null,
        heading: d.currentHeading ?? 0,
        updatedAt: d.locationUpdatedAt ?? null,
      }
    }

    return withCors({
      ride: {
        id: params.id,
        riderName: ride.riderName,
        pickupAddress: ride.pickupAddress,
        dropAddress: ride.dropAddress,
        pickupLat: ride.pickupLat,
        pickupLng: ride.pickupLng,
        dropLat: ride.dropLat,
        dropLng: ride.dropLng,
        routePolyline: ride.routePolyline,
        status: ride.status,
      },
      driver,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
