export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → ride history for the authenticated user, with driver profile + vehicle hydrated
export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    // Paginated: ?limit (1..50, default 50) & ?page (1-based). It used to send
    // the rider's entire history, chat and all, on every home-screen load —
    // the current ride now has its own small endpoint (GET /rides/active).
    const sp = req.nextUrl?.searchParams
    const limit = Math.min(50, Math.max(1, parseInt(sp?.get('limit') || '50', 10) || 50))
    const page = Math.max(1, parseInt(sp?.get('page') || '1', 10) || 1)
    const found = await Ride.find({ riderId: payload.id }).sort({ createdAt: -1 })
      .skip((page - 1) * limit).limit(limit + 1)
      .select('-messages -otpAttempts -dropOtpAttempts -refundLeaseAt -shareToken -offeredHistory -rejectedBy')
      .lean() as any[]
    const hasMore = found.length > limit
    const rides = found.slice(0, limit)

    // Batch-load drivers for all rides that have one
    const driverIds = Array.from(new Set(rides.map(r => r.driverId).filter(Boolean).map(String)))
    const drivers = driverIds.length
      ? await Driver.find({ _id: { $in: driverIds } })
          .select('name phone profilePicUrl vehicleModel vehicleNumber vehicleRegistrationNumber rating')
          .lean() as any[]
      : []
    const dMap = new Map<string, any>(drivers.map(d => [String(d._id), d]))

    // Vehicle images by type name (for the trip detail "car image")
    const vts = await VehicleType.find({}).select('name imageUrl').lean() as any[]
    const vtMap = new Map<string, string>(vts.map(v => [v.name, v.imageUrl || '']))

    const hydrated = rides.map(r => {
      const d = r.driverId ? dMap.get(String(r.driverId)) : null
      // Phone numbers only while the trip is live.
      const live = ["accepted", "arrived", "ongoing"].includes(r.status)
      if (!live) delete r.driverPhone
      return {
        ...r,
        vehicleImageUrl: vtMap.get(r.vehicleType) || '',
        driver: d ? {
          name: d.name,
          phone: live ? d.phone : undefined,
          profilePicUrl: d.profilePicUrl,
          vehicleModel: d.vehicleModel,
          vehicleNumber: d.vehicleNumber || d.vehicleRegistrationNumber,
          rating: d.rating,
        } : null,
      }
    })

    return withCors({ rides: hydrated, page, limit, hasMore })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
