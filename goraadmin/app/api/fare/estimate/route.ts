export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { pickupLat, pickupLng, dropLat, dropLng, service }
// → returns zone + list of vehicles with calculated fare
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

    // Distance & time
    let distance = 5, duration = 15
    if (dropLat != null && dropLng != null) {
      distance = +distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: dropLat, lng: dropLng }).toFixed(1)
      duration = Math.round(distance * 3) // ~3 min/km estimate
    }

    // Calculate fare per active vehicle for this service
    const vehicles = (zone.pricing || [])
      .filter((p: any) => p.service === service)
      .map((p: any) => {
        const baseDist = 2 // free km in base
        const chargeableKm = Math.max(0, distance - baseDist)
        let fare = (p.baseFare || 0) + chargeableKm * (p.perKm || 0) + duration * (p.perMin || 0)
        fare = Math.max(fare, p.minFare || 0)
        fare = Math.round(fare)
        return {
          vehicleTypeId: p.vehicleTypeId,
          name: p.vehicleTypeName,
          fare,
          baseFare: p.baseFare,
          perKm: p.perKm,
          perMin: p.perMin,
          commissionPercent: p.commissionPercent ?? 20,
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
