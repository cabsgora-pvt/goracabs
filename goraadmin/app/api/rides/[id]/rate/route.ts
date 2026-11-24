export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth, requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { rating: 1..5, review? }   (`by` in the body is ignored)
// The side comes from the token: a rider token rates the DRIVER, a driver
// token rates the RIDER. Only on a completed ride, only by its own rider /
// assigned driver, and once per side (409 ALREADY_RATED on a repeat).
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const b = await req.json().catch(() => ({}))
    const asDriver = requireDriverAuth(req) as any
    const asRider = asDriver?.id ? null : (requireRider(req) as any)
    if (!asDriver?.id && !asRider?.id) return withCors({ error: 'Unauthorized' }, 401)

    const n = Number(b?.rating)
    if (b?.rating == null || !Number.isFinite(n)) return withCors({ error: 'rating must be 1 to 5' }, 400)
    const rating = Math.min(5, Math.max(1, Math.round(n)))
    const review = typeof b?.review === 'string' ? b.review.trim().slice(0, 500) : ''

    await connectDB()
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    const ride: any = await Ride.findById(params.id).select('riderId driverId status driverRating riderRating').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const byDriver = !!asDriver?.id
    const mine = byDriver
      ? !!ride.driverId && String(ride.driverId) === String(asDriver.id)
      : !!ride.riderId && String(ride.riderId) === String(asRider.id)
    if (!mine) return withCors({ error: 'Not your ride' }, 403)
    if (ride.status !== 'completed') return withCors({ error: 'You can rate once the ride is completed', code: 'NOT_COMPLETED' }, 409)

    const field = byDriver ? 'riderRating' : 'driverRating'
    const reviewField = byDriver ? 'riderReview' : 'driverReview'
    const res = await Ride.updateOne(
      { _id: ride._id, status: 'completed', [field]: null },
      { $set: { [field]: rating, [reviewField]: review } },
    )
    if (!res.modifiedCount) return withCors({ error: 'Already rated', code: 'ALREADY_RATED' }, 409)

    // A driver's average is recomputed from their rated rides (one aggregate).
    // (Riders have no stored average; the rider's rating stays on the ride.)
    if (!byDriver && ride.driverId) {
      const agg: any[] = await Ride.aggregate([
        { $match: { driverId: new mongoose.Types.ObjectId(String(ride.driverId)), driverRating: { $ne: null } } },
        { $group: { _id: null, avg: { $avg: '$driverRating' } } },
      ])
      if (agg[0]?.avg != null) await Driver.updateOne({ _id: ride.driverId }, { $set: { rating: +Number(agg[0].avg).toFixed(2) } })
    }
    return withCors({ success: true, rated: byDriver ? 'rider' : 'driver', rating })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
