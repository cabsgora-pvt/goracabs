export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAdmin } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { completeRide } from '@/lib/settlement'

export async function OPTIONS() { return corsOptions() }

// Admin escape hatch for a ride that has been priced but never settled — e.g.
// a cash rental where the driver's app died between collecting the money and
// calling /complete. Admin only. It calls the single settlement path
// (lib/settlement.ts completeRide) directly — no HTTP hop, so nothing depends
// on the request's Host header. Same rules as the driver ending the ride: only
// an ongoing ride, and an online ride is left awaiting its payment.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const admin = requireAdmin(req) as any
    if (!admin?.id) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)

    await connectDB()
    const ride: any = await Ride.findById(params.id).select('status').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status === 'completed') return withCors({ error: 'Already completed' }, 400)
    if (ride.status === 'cancelled') return withCors({ error: 'Ride was cancelled' }, 400)

    const out = await completeRide(params.id, { kind: 'admin', id: String(admin.id) })
    return withCors({ forced: true, ...out.body }, out.status)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
