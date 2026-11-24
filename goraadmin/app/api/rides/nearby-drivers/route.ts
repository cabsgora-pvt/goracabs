export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { createHmac } from 'crypto'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

const GRID_DEG = 0.00135   // ≈ 150 m of latitude
const snap = (v: number) => Math.round(Math.round(v / GRID_DEG) * GRID_DEG * 1e5) / 1e5
const BUCKET_MS = 10 * 60 * 1000
function markerId(driverId: string): string {
  const bucket = Math.floor(Date.now() / BUCKET_MS)
  return createHmac('sha256', String(process.env.JWT_SECRET || 'nearby')).update(`nearby:${bucket}:${driverId}`).digest('hex').slice(0, 10)
}

// Public GET → nearby online drivers for the "live vehicles on map" effect.
// Query: ?lat=..&lng=..&radius=<km, default 5>&vehicleType=<optional>
// Returns lightweight markers only (no PII): { drivers: [{ lat, lng, heading, vehicleType }] }
export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url)
    const lat = parseFloat(searchParams.get('lat') || '')
    const lng = parseFloat(searchParams.get('lng') || '')
    const radiusKm = Math.min(Math.max(parseFloat(searchParams.get('radius') || '5') || 5, 1), 25)
    const vehicleType = (searchParams.get('vehicleType') || '').trim()

    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return withCors({ drivers: [] })
    }

    await connectDB()

    // Only drivers seen in the last 5 minutes count as "live" on the map.
    const freshSince = new Date(Date.now() - 5 * 60 * 1000)

    // Rough bounding box first (cheap) — 1 deg lat ≈ 111 km.
    const latDelta = radiusKm / 111
    const lngDelta = radiusKm / (111 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01))

    const query: any = {
      isOnline: true,
      currentLat: { $gte: lat - latDelta, $lte: lat + latDelta },
      currentLng: { $gte: lng - lngDelta, $lte: lng + lngDelta },
      locationUpdatedAt: { $gte: freshSince },
    }
    if (vehicleType) query.selectedVehicleTypeName = vehicleType

    const docs: any[] = await Driver.find(query)
      .select('currentLat currentLng currentHeading selectedVehicleTypeName vehicleType')
      .limit(60)
      .lean()

    // Precise haversine filter + strip to marker-only payload (no PII).
    const R = 6371
    const drivers = docs
      .map((d) => {
        const dLat = ((d.currentLat - lat) * Math.PI) / 180
        const dLng = ((d.currentLng - lng) * Math.PI) / 180
        const a =
          Math.sin(dLat / 2) ** 2 +
          Math.cos((lat * Math.PI) / 180) *
            Math.cos((d.currentLat * Math.PI) / 180) *
            Math.sin(dLng / 2) ** 2
        const dist = 2 * R * Math.asin(Math.min(1, Math.sqrt(a)))
        return {
          // Marker key: an HMAC of the driver id and a 10-minute time bucket.
          // Stable enough for the app to animate a marker across polls, but it
          // changes every bucket and cannot be linked back to a driver.
          id: markerId(String(d._id)),
          // Snapped to a ~150 m grid: the map shows "cars around", not where
          // a particular driver is parked.
          lat: snap(d.currentLat),
          lng: snap(d.currentLng),
          heading: d.currentHeading || 0,
          vehicleType: d.selectedVehicleTypeName || d.vehicleType || '',
          _dist: dist,
        }
      })
      .filter((d) => d._dist <= radiusKm)
      .sort((a, b) => a._dist - b._dist)
      .slice(0, 40)
      .map(({ _dist, ...rest }) => rest)

    return withCors({ drivers })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error', drivers: [] }, 500)
  }
}
