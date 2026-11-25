export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'
import { ACTIVE_STATUSES, isShareToken } from '@/lib/ride-view'
import { rateLimitAsync } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

// Keeps the last parts of an address (area, city), dropping the house/street.
function areaOf(addr: any): string {
  const parts = String(addr || '').split(',').map(s => s.trim()).filter(Boolean)
  if (parts.length <= 2) return parts.join(', ')
  return parts.slice(-3).join(', ')
}
const coarse = (v: any) => (typeof v === 'number' ? Math.round(v * 1000) / 1000 : null)   // ~110 m

const TRACK_RATE = { LIMIT: 60, WINDOW_MS: 60_000 }

// GET /api/rides/track/{shareToken} — public share link (no auth).
// The path segment is the ride's random shareToken (GET /api/rides/{id}/share-token
// gives it to the rider), NOT the ride id: ride ids are sequential-ish and
// visible to drivers, so tracking by id let anyone follow any live trip.
// Only while the ride is live (accepted / arrived / ongoing). Gives the rider's
// first name, the pickup/drop AREA with coarse coordinates and the driver's
// first name, vehicle and live position. No phone numbers, no plate, no exact
// addresses, no route polyline. Any other status returns
// { ride: { status, active: false }, driver: null }. Rate limited per IP.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!(await rateLimitAsync(req, 'ride-track', TRACK_RATE.LIMIT, TRACK_RATE.WINDOW_MS))) {
      return withCors({ error: 'Too many requests', code: 'RATE_LIMITED' }, 429)
    }
    // Installed rider apps (≤ v1.5.0) share /track/<rideId>. Until they are
    // updated (then set STRICT_TRACK_TOKEN=1), a ride id still works — the reply
    // is the same coarse, phone-free view and only while the ride is live.
    const legacyId = process.env.STRICT_TRACK_TOKEN !== '1' && /^[a-f0-9]{24}$/.test(params.id)
    if (!legacyId && !isShareToken(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()
    const ride: any = await Ride.findOne(legacyId ? { _id: params.id } : { shareToken: params.id })
      .select('riderName pickupAddress dropAddress pickupLat pickupLng dropLat dropLng status driverId driverName')
      .lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (!ACTIVE_STATUSES.includes(ride.status)) {
      return withCors({ ride: { status: ride.status, active: false }, driver: null })
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
        active: true,
        riderName: String(ride.riderName || '').split(' ')[0],
        pickupAddress: areaOf(ride.pickupAddress),
        dropAddress: areaOf(ride.dropAddress),
        pickupLat: coarse(ride.pickupLat),
        pickupLng: coarse(ride.pickupLng),
        dropLat: coarse(ride.dropLat),
        dropLng: coarse(ride.dropLng),
        status: ride.status,
      },
      driver,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
