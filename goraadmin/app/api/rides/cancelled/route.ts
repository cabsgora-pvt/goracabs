export const dynamic = 'force-dynamic'
import { NextResponse , NextRequest} from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

// Admin pages only. It answered anyone with every matching ride and rider.
export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    // Paged (?page=&limit=, max 200); the reason stats still cover every
    // cancelled ride, computed in Mongo instead of loading them all.
    const { page, limit, skip } = parsePaging(req.nextUrl.searchParams, 100)
    const q = { status: 'cancelled' }
    const [rides, total, stats] = await Promise.all([
      Ride.find(q).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
      Ride.countDocuments(q),
      Ride.aggregate([
        { $match: q },
        { $group: { _id: { $ifNull: ['$cancellationReason', 'Unknown reason'] }, count: { $sum: 1 }, cancelledBy: { $first: { $ifNull: ['$cancelledBy', 'System'] } } } },
        { $sort: { count: -1 } }, { $limit: 10 },
      ]),
    ])
    const cancellationReasons = stats.map((s: any) => ({ reason: s._id || 'Unknown reason', count: s.count, cancelledBy: s.cancelledBy }))

    return NextResponse.json({ rides, cancellationReasons, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
