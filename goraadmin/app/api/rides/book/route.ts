export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST booking → creates ride, assigns nearest online driver in same zone
export async function POST(req: NextRequest) {
  try {
    const b = await req.json()
    await connectDB()

    // Generate ride OTP
    const otp = Math.floor(1000 + Math.random() * 9000).toString()

    const ride = await Ride.create({
      riderId: b.riderId, riderName: b.riderName, riderPhone: b.riderPhone,
      pickupAddress: b.pickupAddress, dropAddress: b.dropAddress,
      pickupLat: b.pickupLat, pickupLng: b.pickupLng,
      dropLat: b.dropLat, dropLng: b.dropLng,
      service: b.service || 'taxi', vehicleType: b.vehicleType,
      fare: b.fare, distance: b.distance, duration: b.duration,
      paymentMode: b.paymentMode || 'cash',
      zoneId: b.zoneId, otp, status: 'pending',
    })

    // Find nearest online approved driver: same zone + vehicle type
    const drivers = await Driver.find({
      status: 'approved', isOnline: true,
      zoneId: b.zoneId,
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
      ride: { id: ride._id, otp, status: 'pending' },
      driverFound: !!nearest,
      driver: nearest ? { id: nearest._id, name: nearest.name, phone: nearest.phone, distanceKm: +nd.toFixed(1) } : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
