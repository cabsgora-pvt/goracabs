export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → ride history for the authenticated user
export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const rides = await Ride.find({ riderId: payload.id }).sort({ createdAt: -1 }).lean()
    return withCors({ rides })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
