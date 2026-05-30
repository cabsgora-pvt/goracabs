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

    const query: any = {
      status: 'pending',
      vehicleType: driver.selectedVehicleTypeName,
      createdAt: { $gte: twoMinAgo },
      rejectedBy: { $ne: driverId },
    }
    // Match by zone (stored as string on driver, ObjectId on ride)
    if (driver.zoneId) query.zoneId = driver.zoneId

    const rides = await Ride.find(query).sort({ createdAt: -1 }).lean()

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
      }
    })

    return withCors({ rides: result })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
