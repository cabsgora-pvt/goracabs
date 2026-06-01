export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → pending ride requests this driver may accept (same zone + vehicle type, recent, not rejected)
// Also returns rider's profile photo so the driver app can show their face on incoming request.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000)
    const driverId = String(driver._id)

    // Build a $or so drivers see BOTH their in-city taxi rides AND outstation rides
    // (when they've opted in). Existing taxi flow is untouched — drivers who haven't
    // opted into outstation see only the taxi branch.
    const baseFilter: any = {
      vehicleType: driver.selectedVehicleTypeName,
    }
    const taxiBranch: any = { ...baseFilter, service: { $ne: 'outstation' } }
    if (driver.zoneId) taxiBranch.zoneId = driver.zoneId

    const branches: any[] = [taxiBranch]
    if (driver.acceptsOutstation) {
      // Outstation: ignore zone restriction (cross-city), allow longer window (15 min)
      branches.push({ ...baseFilter, service: 'outstation' })
    }

    const query: any = {
      status: 'pending',
      createdAt: { $gte: new Date(Date.now() - 15 * 60 * 1000) }, // widest window; per-branch filtering above handles other cases
      rejectedBy: { $ne: driverId },
      $or: branches,
    }

    // For non-outstation taxi rides we still want the 2-min freshness — apply after fetch
    let rides = await Ride.find(query).sort({ createdAt: -1 }).lean() as any[]
    rides = rides.filter((r: any) => {
      if (r.service === 'outstation') return true // outstation rides stay valid up to 15 min
      return new Date(r.createdAt) >= twoMinAgo
    })

    // Batch-load rider profile pics
    const riderIds = Array.from(new Set(rides.map((r: any) => String(r.riderId)).filter(Boolean)))
    const users = riderIds.length
      ? await User.find({ _id: { $in: riderIds } }).select('profilePicUrl rating').lean()
      : []
    const userMap = new Map<string, any>(users.map((u: any) => [String(u._id), u]))

    const result = rides.map((r: any) => {
      const u = r.riderId ? userMap.get(String(r.riderId)) : null
      return {
        id: r._id,
        riderName: r.riderName,
        riderPhone: r.riderPhone,
        riderProfilePicUrl: u?.profilePicUrl || '',
        riderRating: u?.rating ?? null,
        pickupAddress: r.pickupAddress,
        dropAddress: r.dropAddress,
        pickupLat: r.pickupLat, pickupLng: r.pickupLng,
        dropLat: r.dropLat, dropLng: r.dropLng,
        fare: r.fare,
        tip: r.tip,
        totalFare: r.totalFare,
        distance: r.distance,
        duration: r.duration,
        vehicleType: r.vehicleType,
        paymentMode: r.paymentMode,
        routePolyline: r.routePolyline,
        createdAt: r.createdAt,
        // Outstation extras (null for taxi rides — driver UI hides outstation chip)
        service: r.service,
        tripType: r.tripType,
        cityFrom: r.cityFrom,
        cityTo: r.cityTo,
        departureAt: r.departureAt,
        returnAt: r.returnAt,
      }
    })

    return withCors({ rides: result })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
