export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { pointInPolygon } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'
import { isFranchiseMode } from '@/lib/franchise'

export async function OPTIONS() { return corsOptions() }

// GET ?lat=&lng= — public. The helpline for the zone the rider is in, set by
// that zone's admin (franchise). Only the zone name and number leave here.
export async function GET(req: NextRequest) {
  try {
    const lat = Number(req.nextUrl.searchParams.get('lat'))
    const lng = Number(req.nextUrl.searchParams.get('lng'))
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return withCors({ error: 'lat and lng required' }, 400)
    // Zone helplines belong to franchises; with franchise mode off the app
    // shows Gora's own support number.
    if (!(await isFranchiseMode())) return withCors({ found: false })
    await connectDB()
    const zones: any[] = await Zone.find({ isActive: true }).select('name polygonPath supportPhone').lean()
    const z = zones.find(z => (z.polygonPath?.length || 0) >= 3 && pointInPolygon({ lat, lng }, z.polygonPath))
    if (!z) return withCors({ found: false })
    return withCors({ found: true, zone: z.name, supportPhone: z.supportPhone || '' })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
