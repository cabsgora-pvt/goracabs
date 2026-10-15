export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { waitingSecondsFor, secondsSince } from '@/lib/ride-phase'

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
      // Server-computed so the driver's resumed waiting timer is not thrown off
      // by the phone's clock. Null unless the driver is waiting at pickup.
      waitingSec: waitingSecondsFor(r),

      // ── Where an in-progress job had got to ──
      // A reopened ride screen used to know none of this and started each job
      // over: a rental's clock read 0:00, a parcel already on its way asked to
      // be collected again, a round trip at its destination asked the driver to
      // swipe "arrived at destination" a second time, and a multi-stop ride
      // went back to stop 1. Read-only: nothing here changes the ride.
      awaitingPayment: !!r.awaitingPayment,
      // Rental
      rentalPhase: r.rentalPhase, isWaiting: !!r.isWaiting,
      actualKm: r.actualKm, actualHours: r.actualHours,
      rentalStops: r.rentalStops || [],
      rentalStartedAt: r.rentalStartedAt,
      rentalElapsedSec: secondsSince(r.rentalStartedAt),
      // Hire
      hirePhase: r.hirePhase, hireActualHours: r.hireActualHours,
      hireStartedAt: r.hireStartedAt,
      hireElapsedSec: secondsSince(r.hireStartedAt),
      // Delivery
      deliveryPhase: r.deliveryPhase,
      // Outstation round trip
      outstationPhase: r.outstationPhase, nightHaltConfirmed: !!r.nightHaltConfirmed,
      // Multi-stop
      currentStopIndex: r.currentStopIndex ?? 0, isWaitingAtStop: !!r.isWaitingAtStop,
      // Outstation tolls entered so far
      tolls: (r.tolls || []).map((t: any) => ({
        id: String(t._id), amount: t.amount, at: t.at, source: t.source,
        place: t.place || '', reported: !!t.reportedAt,
      })),
      tollCharge: r.tollCharge || 0,
    }
    return withCors({ ride })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
