export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
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
    }).sort({ createdAt: -1 }).lean()
    return withCors({ rides })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
