export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { requireActiveRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { evaluatePromo } from '@/lib/promo'
import { distanceKm, pointInPolygon } from '@/lib/geo'

export async function OPTIONS() { return corsOptions() }

const SERVICES = ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver']

// The zone of a pickup, exactly as /rides/book finds it: the zone whose polygon
// contains it, else the nearest zone centre within 25 km.
async function zoneOfPickup(lat: number, lng: number): Promise<any> {
  const zones = await Zone.find({ isActive: true }).select('_id polygonPath centerLat centerLng').lean() as any[]
  for (const z of zones) {
    if (z.polygonPath?.length >= 3 && pointInPolygon({ lat, lng }, z.polygonPath)) return z
  }
  let best: any = null, nd = Infinity
  for (const z of zones) {
    const d = distanceKm({ lat, lng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
    if (d < nd) { nd = d; best = z }
  }
  return nd > 25 ? null : best
}

// POST /api/promos/preview  (rider token)
// body: { code, service, fare, tip?, pickupLat?, pickupLng?, zoneId? }
// → { valid, discount, reason?, code, fare, tip, payable }
//
// What the server WILL give for this code on this fare — the exact
// evaluatePromo rules /rides/book applies (zone, expiry, usage caps, minimum
// fare, per-rider use, service). Nothing is redeemed. For an outstation trip
// paid upfront, `payable` (fare + tip − discount) is exactly what the booking
// requires the rider to prepay. Pass the pickup (as book does); zoneId is used
// only when no pickup is given.
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveRider(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const b = await req.json().catch(() => ({}))
    const code = String(b?.code || '').trim()
    if (!code) return withCors({ error: 'Enter a code', code: 'codeRequired' }, 400)
    const service = String(b?.service || 'taxi')
    if (!SERVICES.includes(service)) return withCors({ error: 'Unknown service' }, 400)
    const fare = Number(b?.fare)
    if (!Number.isFinite(fare) || fare <= 0) return withCors({ error: 'Invalid fare', code: 'invalidFare' }, 400)
    const tipN = b?.tip == null || b.tip === '' ? 0 : Number(b.tip)
    const tip = Number.isFinite(tipN) && tipN > 0 ? Math.round(tipN) : 0

    await connectDB()
    let zoneId: any = undefined
    const lat = Number(b?.pickupLat), lng = Number(b?.pickupLng)
    if (b?.pickupLat != null && b?.pickupLng != null && Number.isFinite(lat) && Number.isFinite(lng)) {
      zoneId = (await zoneOfPickup(lat, lng))?._id
    } else if (b?.zoneId && mongoose.isValidObjectId(String(b.zoneId))) {
      zoneId = String(b.zoneId)
    }

    const p = await evaluatePromo(code, fare, zoneId, { service, riderId: auth.id })
    const discount = p.applied ? p.discount : 0
    return withCors({
      valid: !!p.applied, discount, ...(p.reason ? { reason: p.reason } : {}),
      code: p.code, fare, tip,
      payable: Math.max(0, Math.round(fare + tip - discount)),
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
