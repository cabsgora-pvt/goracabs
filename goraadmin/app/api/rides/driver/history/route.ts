export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import User from '@/models/User'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → completed/cancelled ride history for the authenticated driver
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const rides = await Ride.find({
      driverId: payload.id,
      status: { $in: ['completed', 'cancelled'] },
    }).sort({ createdAt: -1 }).lean() as any[]

    // riderName/riderPhone are snapshotted on the ride at booking time, but the
    // rider's profile photo isn't — same batch-join /api/rides/user already
    // does for the driver's photo on the rider's own history, mirrored here so
    // the driver's trip history can show a real photo instead of an initial.
    const riderIds = Array.from(new Set(rides.map(r => r.riderId).filter(Boolean).map(String)))
    const riders = riderIds.length
      ? await User.find({ _id: { $in: riderIds } }).select('profilePicUrl').lean() as any[]
      : []
    const picById = new Map<string, string>(riders.map(u => [String(u._id), u.profilePicUrl || '']))
    const hydrated = rides.map(r => ({
      ...r,
      riderProfilePicUrl: r.riderId ? (picById.get(String(r.riderId)) || '') : '',
    }))

    return withCors({ rides: hydrated })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
