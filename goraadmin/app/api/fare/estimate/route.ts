export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { pickupLat, pickupLng, dropLat, dropLng, service }
// → returns zone + list of vehicles with calculated fare + real ETA (nearest driver) per vehicle type
export async function POST(req: NextRequest) {
  try {
    const { pickupLat, pickupLng, dropLat, dropLng, service = 'taxi' } = await req.json()
    if (pickupLat == null || pickupLng == null) return withCors({ error: 'pickup required' }, 400)

    await connectDB()
    const zones = await Zone.find({ isActive: true }).lean() as any[]

    // Find zone for pickup
    let zone: any = null
    for (const z of zones) {
      if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: pickupLat, lng: pickupLng }, z.polygonPath)) {
        zone = z; break
      }
    }
    if (!zone) {
      let nd = Infinity
      for (const z of zones) {
        const d = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
        if (d < nd) { nd = d; zone = z }
      }
      if (!zone || nd > 25) return withCors({ available: false, message: 'Service not available here' })
    }

    // Distance & time (Haversine — replaced by Directions API at booking time)
    let distance = 5, duration = 15
    if (dropLat != null && dropLng != null) {
      distance = +distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: dropLat, lng: dropLng }).toFixed(1)
      duration = Math.round(distance * 3) // ~3 min/km estimate
    }

    // Load all approved+online drivers in this zone (one query, then bucket by vehicle type)
    const onlineDrivers: any[] = await Driver.find({
      status: 'approved',
      isOnline: true,
      zoneId: String(zone._id),
      currentLat: { $ne: null },
      currentLng: { $ne: null },
    }).select('selectedVehicleTypeName currentLat currentLng').lean()

    // For each vehicle type → nearest driver km + estimated min (assume ~30 km/h city avg)
    const nearestByType = new Map<string, { km: number; min: number }>()
    for (const d of onlineDrivers) {
      const t = d.selectedVehicleTypeName
      if (!t) continue
      const km = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: d.currentLat, lng: d.currentLng })
      const prev = nearestByType.get(t)
      if (!prev || km < prev.km) {
        // 30 km/h ≈ 2 min/km — clamp 1..30
        const min = Math.max(1, Math.min(30, Math.round(km * 2)))
        nearestByType.set(t, { km: +km.toFixed(1), min })
      }
    }

    // Calculate fare + attach ETA per active vehicle for this service
    const vehicles = (zone.pricing || [])
      .filter((p: any) => p.service === service)
      .map((p: any) => {
        const baseDist = 2 // free km in base
        const chargeableKm = Math.max(0, distance - baseDist)
        let fare = (p.baseFare || 0) + chargeableKm * (p.perKm || 0) + duration * (p.perMin || 0)
        fare = Math.max(fare, p.minFare || 0)
        fare = Math.round(fare)
        const eta = nearestByType.get(p.vehicleTypeName)
        return {
          vehicleTypeId: p.vehicleTypeId,
          name: p.vehicleTypeName,
          fare,
          baseFare: p.baseFare,
          perKm: p.perKm,
          perMin: p.perMin,
          commissionPercent: p.commissionPercent ?? 20,
          // null = no driver currently available of this type
          etaMin: eta ? eta.min : null,
          driverDistanceKm: eta ? eta.km : null,
        }
      })

    return withCors({
      available: true,
      zone: { id: zone._id, name: zone.name },
      distance, duration, service,
      vehicles,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
