export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { createHmac } from 'crypto'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { withCors, corsOptions } from '@/lib/cors'
import { rateLimitAsync } from '@/lib/rate-limit'
import { serviceOptInFilter } from '@/lib/dispatch'

// Services a rider can book; `service` narrows the map to drivers who could
// take that service (vehicle types the admin enabled for it + the driver's own
// opt-in), so a parcel booking shows parcel vehicles, not every cab in town.
const SERVICES = new Set(['taxi', 'delivery', 'rental', 'outstation', 'hire_driver'])
let vtCache: { at: number; byService: Map<string, string[]> } | null = null
async function vehicleTypesFor(service: string): Promise<string[]> {
  if (!vtCache || Date.now() - vtCache.at > 60_000) {
    const all: any[] = await VehicleType.find({ isActive: { $ne: false } }).select('name services').lean()
    const byService = new Map<string, string[]>()
    for (const v of all) for (const s of (v.services || ['taxi'])) {
      const k = s === 'parcel' ? 'delivery' : s
      byService.set(k, [...(byService.get(k) || []), v.name])
    }
    vtCache = { at: Date.now(), byService }
  }
  return vtCache.byService.get(service) || []
}

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
    // Public and polled by every open rider home screen: per-IP limit.
    if (!(await rateLimitAsync(req, 'nearby-drivers', 120, 60_000))) {
      return withCors({ error: 'Too many requests', code: 'RATE_LIMITED', drivers: [] }, 429)
    }
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

    // Equality fields first, then the fresh-fix range: served by the
    // { isOnline, status, locationUpdatedAt } index (models/Driver).
    const query: any = {
      isOnline: true,
      status: 'approved',
      locationUpdatedAt: { $gte: freshSince },
      currentLat: { $gte: lat - latDelta, $lte: lat + latDelta },
      currentLng: { $gte: lng - lngDelta, $lte: lng + lngDelta },
    }
    if (vehicleType) query.selectedVehicleTypeName = vehicleType
    const service = (searchParams.get('service') || '').trim()
    if (SERVICES.has(service)) {
      Object.assign(query, serviceOptInFilter(service))
      if (!vehicleType) query.selectedVehicleTypeName = { $in: await vehicleTypesFor(service) }
    }

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
