export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'
import { ACTIVE_STATUSES } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

// Keeps the last parts of an address (area, city), dropping the house/street.
function areaOf(addr: any): string {
  const parts = String(addr || '').split(',').map(s => s.trim()).filter(Boolean)
  if (parts.length <= 2) return parts.join(', ')
  return parts.slice(-3).join(', ')
}
const coarse = (v: any) => (typeof v === 'number' ? Math.round(v * 1000) / 1000 : null)   // ~110 m

// GET /api/rides/track/{id} — public share link (no auth).
// Only while the ride is live (accepted / arrived / ongoing). Gives the rider's
// first name, the pickup/drop AREA with coarse coordinates, the route, and the
// driver's first name, vehicle and live position. No phone numbers, no plate,
// no exact addresses. Any other status returns { ride: { id, status }, driver: null }.
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()
    const ride: any = await Ride.findById(params.id)
      .select('riderName pickupAddress dropAddress pickupLat pickupLng dropLat dropLng routePolyline status driverId driverName')
      .lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (!ACTIVE_STATUSES.includes(ride.status)) {
      return withCors({ ride: { id: params.id, status: ride.status, active: false }, driver: null })
    }

    let driver: any = null
    if (ride.driverId) {
      const d: any = await Driver.findById(ride.driverId)
        .select('currentLat currentLng currentHeading locationUpdatedAt vehicleModel selectedVehicleTypeName')
        .lean()
      if (d) driver = {
        name: String(ride.driverName || '').split(' ')[0],
        vehicleModel: d.vehicleModel || '',
        vehicleType: d.selectedVehicleTypeName || '',
        lat: d.currentLat ?? null,
        lng: d.currentLng ?? null,
        heading: d.currentHeading ?? 0,
        updatedAt: d.locationUpdatedAt ?? null,
      }
    }

    return withCors({
      ride: {
        id: params.id,
        active: true,
        riderName: String(ride.riderName || '').split(' ')[0],
        pickupAddress: areaOf(ride.pickupAddress),
        dropAddress: areaOf(ride.dropAddress),
        pickupLat: coarse(ride.pickupLat),
        pickupLng: coarse(ride.pickupLng),
        dropLat: coarse(ride.dropLat),
        dropLng: coarse(ride.dropLng),
        routePolyline: ride.routePolyline,
        status: ride.status,
      },
      driver,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
