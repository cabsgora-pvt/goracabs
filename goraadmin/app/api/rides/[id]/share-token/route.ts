export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { newShareToken } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/{id}/share-token — the ride's RIDER only.
// → { shareToken, path: '/track/<shareToken>' }. The token is made at accept,
// or here on first request; the public tracker (GET /api/rides/track/{token},
// web page /track/{token}) only answers to it, never to the ride id.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const u = requireRider(req) as any
    if (!u?.id) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()
    let ride: any = await Ride.findById(params.id).select('riderId shareToken status').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (String(ride.riderId || '') !== String(u.id)) return withCors({ error: 'Not your ride', code: 'NOT_PARTICIPANT' }, 403)
    if (!ride.shareToken) {
      await Ride.updateOne({ _id: ride._id, shareToken: null }, { $set: { shareToken: newShareToken() } })
      ride = await Ride.findById(params.id).select('shareToken status').lean()
    }
    return withCors({ shareToken: ride.shareToken, path: `/track/${ride.shareToken}`, status: ride.status })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
