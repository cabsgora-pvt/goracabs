export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import User from '@/models/User'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Only what the trip list / earnings screens show. Never the OTPs, the chat,
// the rider's phone or any internal bookkeeping.
const HISTORY_FIELDS = [
  'status', 'service', 'vehicleType', 'tripType', 'cityFrom', 'cityTo', 'numPassengers',
  'riderName', 'riderId', 'pickupAddress', 'dropAddress', 'distance', 'duration',
  'fare', 'tip', 'totalFare', 'finalFare', 'hireFinalFare', 'deliveryFinalFare',
  'driverEarning', 'commissionAmount', 'paymentMode', 'paymentStatus',
  'riderRating', 'driverRating', 'driverReview', 'tollCharge', 'waitingChargeTotal',
  'cancelledBy', 'cancellationReason', 'cancellationFee',
  'createdAt', 'acceptedAt', 'startedAt', 'completedAt', 'scheduledAt', 'departureAt',
].join(' ')

const HISTORY_MAX_LIMIT = 50

// GET ?page=1&limit=50 → completed/cancelled rides of the authenticated driver,
// newest first, paginated (limit ≤ 50, default 50).
// → { rides, page, limit, hasMore }
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const sp = new URL(req.url).searchParams
    const page = Math.max(1, Math.min(1000, parseInt(sp.get('page') || '1', 10) || 1))
    const limit = Math.max(1, Math.min(HISTORY_MAX_LIMIT, parseInt(sp.get('limit') || String(HISTORY_MAX_LIMIT), 10) || HISTORY_MAX_LIMIT))

    await connectDB()
    const rows = await Ride.find({
      driverId: payload.id,
      status: { $in: ['completed', 'cancelled'] },
    }).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit + 1).select(HISTORY_FIELDS).lean() as any[]
    const hasMore = rows.length > limit
    const rides = rows.slice(0, limit)

    // The rider's profile photo isn't snapshotted on the ride; one batched
    // lookup for the page (no per-ride query).
    const riderIds = Array.from(new Set(rides.map(r => r.riderId).filter(Boolean).map(String)))
    const riders = riderIds.length
      ? await User.find({ _id: { $in: riderIds } }).select('profilePicUrl').lean() as any[]
      : []
    const picById = new Map<string, string>(riders.map(u => [String(u._id), u.profilePicUrl || '']))
    const hydrated = rides.map(({ riderId, ...r }) => ({
      ...r,
      riderProfilePicUrl: riderId ? (picById.get(String(riderId)) || '') : '',
    }))

    return withCors({ rides: hydrated, page, limit, hasMore })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
