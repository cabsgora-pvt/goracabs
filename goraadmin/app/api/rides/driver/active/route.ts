export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// The driver's current in-progress ride (if any) — used to resume the ride
// screen when the app is reopened.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const r: any = await Ride.findOne({
      driverId: payload.id,
      status: { $in: ['accepted', 'arrived', 'ongoing'] },
    })
      .sort({ createdAt: -1 })
      .lean()
    if (!r) return withCors({ ride: null })
    // Format like /pending so the app's RideRequestModel.fromJson works.
    const ride = {
      id: r._id,
      riderName: r.riderName, riderPhone: r.riderPhone,
      pickupAddress: r.pickupAddress, dropAddress: r.dropAddress,
      pickupLat: r.pickupLat, pickupLng: r.pickupLng, dropLat: r.dropLat, dropLng: r.dropLng,
      fare: r.fare, tip: r.tip, totalFare: r.totalFare, distance: r.distance, duration: r.duration,
      vehicleType: r.vehicleType, paymentMode: r.paymentMode, routePolyline: r.routePolyline,
      status: r.status, otp: r.otp, createdAt: r.createdAt, stops: r.stops,
      service: r.service, tripType: r.tripType, cityFrom: r.cityFrom, cityTo: r.cityTo,
      departureAt: r.departureAt, returnAt: r.returnAt, numPassengers: r.numPassengers,
      packageHours: r.packageHours, packageKm: r.packageKm,
      hireTotalHours: r.hireTotalHours, transmission: r.transmission, hireStartAt: r.hireStartAt, hireEndAt: r.hireEndAt,
      senderName: r.senderName, senderPhone: r.senderPhone, receiverName: r.receiverName, receiverPhone: r.receiverPhone,
      itemType: r.itemType, weightKg: r.weightKg, packageSize: r.packageSize, isFragile: r.isFragile,
      codAmount: r.codAmount, parcelPhotos: r.parcelPhotos,
    }
    return withCors({ ride })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
