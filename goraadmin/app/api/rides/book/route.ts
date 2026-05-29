export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Zone from '@/models/Zone'
import { distanceKm, pointInPolygon } from '@/lib/geo'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST booking → creates ride (status pending). Online matching drivers pick it up via polling.
export async function POST(req: NextRequest) {
  try {
    const b = await req.json()
    await connectDB()

    // Identify the rider from the auth token (falls back to body fields)
    const auth = requireAuth(req) as any
    let riderId = b.riderId
    let riderName = b.riderName
    let riderPhone = b.riderPhone
    if (auth?.id) {
      riderId = auth.id
      const user: any = await User.findById(auth.id).lean().catch(() => null)
      if (user) {
        riderName = riderName || user.name
        riderPhone = riderPhone || user.phone
      }
    }

    // Generate ride OTP
    const otp = Math.floor(1000 + Math.random() * 9000).toString()

    const fare = b.fare || 0
    const tip = b.tip || 0
    const totalFare = fare + tip

    const service = b.service || 'taxi'

    // Resolve zone: use provided zoneId, else auto-detect from pickup coords
    let zone: any = null
    if (b.zoneId) {
      zone = await Zone.findById(b.zoneId).lean().catch(() => null)
    }
    if (!zone && b.pickupLat != null && b.pickupLng != null) {
      const zones = await Zone.find({ isActive: true }).lean() as any[]
      for (const z of zones) {
        if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: b.pickupLat, lng: b.pickupLng }, z.polygonPath)) {
          zone = z; break
        }
      }
      if (!zone) {
        let nd = Infinity
        for (const z of zones) {
          const d = distanceKm({ lat: b.pickupLat, lng: b.pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
          if (d < nd) { nd = d; zone = z }
        }
        if (nd > 25) zone = null
      }
    }
    const zoneId = b.zoneId || (zone ? zone._id : undefined)

    // Look up commission % from the zone pricing for this vehicle + service
    let commissionPercent = 20
    if (zone?.pricing) {
      const p = zone.pricing.find((x: any) => x.vehicleTypeName === b.vehicleType && x.service === service)
      if (p?.commissionPercent != null) commissionPercent = p.commissionPercent
    }

    const ride = await Ride.create({
      riderId, riderName, riderPhone,
      pickupAddress: b.pickupAddress, dropAddress: b.dropAddress,
      pickupLat: b.pickupLat, pickupLng: b.pickupLng,
      dropLat: b.dropLat, dropLng: b.dropLng,
      service, vehicleType: b.vehicleType,
      fare, tip, totalFare, commissionPercent,
      distance: b.distance, duration: b.duration,
      paymentMode: b.paymentMode || 'cash',
      zoneId, otp, status: 'pending',
    })

    // Find nearest online approved driver: same zone + vehicle type
    const drivers = await Driver.find({
      status: 'approved', isOnline: true,
      ...(zoneId ? { zoneId: String(zoneId) } : {}),
      selectedVehicleTypeName: b.vehicleType,
    }).lean() as any[]

    let nearest: any = null, nd = Infinity
    for (const d of drivers) {
      if (d.currentLat == null) continue
      const dist = distanceKm({ lat: b.pickupLat, lng: b.pickupLng }, { lat: d.currentLat, lng: d.currentLng })
      if (dist < nd) { nd = dist; nearest = d }
    }

    return withCors({
      success: true,
      ride: { id: ride._id, otp, status: 'pending', fare, tip, totalFare, commissionPercent },
      driverFound: !!nearest,
      driver: nearest ? { id: nearest._id, name: nearest.name, phone: nearest.phone, distanceKm: +nd.toFixed(1) } : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
