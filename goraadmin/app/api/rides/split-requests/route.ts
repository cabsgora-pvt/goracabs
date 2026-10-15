export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

function normPhone(p: string): string {
  const digits = String(p || '').replace(/\D/g, '')
  return digits.slice(-10)
}

// GET /api/rides/split-requests → rides where the caller was added as a
// split partner and hasn't paid yet. Pull-based (the rider app has no push
// notifications), so this is meant to be checked from a "Split Requests" list.
export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const myPhone = normPhone(payload.phone || '')
    if (!myPhone) return withCors({ requests: [] })

    await connectDB()
    const rides: any[] = await Ride.find({ 'splitRequests.phone': myPhone, 'splitRequests.status': 'pending' })
      .select('riderName pickupAddress dropAddress vehicleType driverName createdAt splitRequests')
      .sort({ createdAt: -1 })
      .limit(50)
      .lean()

    const requests = rides.flatMap((r) =>
      (r.splitRequests || [])
        .filter((s: any) => s.phone === myPhone && s.status === 'pending')
        .map((s: any) => ({
          rideId: r._id,
          riderName: r.riderName,
          pickupAddress: r.pickupAddress,
          dropAddress: r.dropAddress,
          vehicleType: r.vehicleType,
          driverName: r.driverName,
          createdAt: r.createdAt,
          share: s.share,
        }))
    )
    return withCors({ requests })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
