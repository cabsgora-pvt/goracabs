export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { lat, lng } → returns the zone the point falls in (or nearest active zone)
export async function POST(req: NextRequest) {
  try {
    const { lat, lng } = await req.json()
    if (lat == null || lng == null) return withCors({ error: 'lat and lng required' }, 400)

    await connectDB()
    const zones = await Zone.find({ isActive: true }).lean() as any[]

    // 1. Exact match — point inside polygon
    for (const z of zones) {
      if (z.polygonPath?.length >= 3 && pointInPolygon({ lat, lng }, z.polygonPath)) {
        return withCors({ found: true, zone: z })
      }
    }

    // 2. Fallback — nearest zone center within 25km
    let nearest: any = null
    let nearestDist = Infinity
    for (const z of zones) {
      const d = distanceKm({ lat, lng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
      if (d < nearestDist) { nearestDist = d; nearest = z }
    }
    if (nearest && nearestDist <= 25) {
      return withCors({ found: true, zone: nearest, approximate: true })
    }

    return withCors({ found: false, message: 'Service not available in this area' })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
