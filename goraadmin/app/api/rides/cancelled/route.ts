export const dynamic = 'force-dynamic'
import { NextResponse , NextRequest} from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Admin pages only. It answered anyone with every matching ride and rider.
//
// GET ?page&limit&search&dateFrom&dateTo (IST days) →
//   { rides, cancellationReasons, total, page, limit, stats: { total, byCancelledBy } }
// Paged (max 200); the reason / who-cancelled stats cover every cancelled ride
// matching the filter, computed in Mongo instead of loading them all.
export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 100)
    const q: any = { status: 'cancelled' }
    const day = /^\d{4}-\d{2}-\d{2}$/
    const dateFrom = (sp.get('dateFrom') || '').trim(), dateTo = (sp.get('dateTo') || '').trim()
    if ((dateFrom && !day.test(dateFrom)) || (dateTo && !day.test(dateTo))) return NextResponse.json({ error: 'dates must be YYYY-MM-DD' }, { status: 400 })
    if (dateFrom || dateTo) {
      q.createdAt = {}
      if (dateFrom) q.createdAt.$gte = new Date(`${dateFrom}T00:00:00.000+05:30`)
      if (dateTo) q.createdAt.$lte = new Date(`${dateTo}T23:59:59.999+05:30`)
    }
    const search = escapeRegex((sp.get('search') || '').trim())
    if (search) {
      const rx = { $regex: search, $options: 'i' }
      q.$or = [{ riderName: rx }, { driverName: rx }, { riderPhone: rx }, { cancellationReason: rx },
        ...(/^[a-f0-9]{24}$/i.test(search) ? [{ _id: new mongoose.Types.ObjectId(search) }] : [])]
    }
    const [rides, total, stats, by] = await Promise.all([
      Ride.find(q).sort({ createdAt: -1 }).skip(skip).limit(limit).select('-messages -routePolyline').lean(),
      Ride.countDocuments(q),
      Ride.aggregate([
        { $match: q },
        { $group: { _id: { $ifNull: ['$cancellationReason', 'Unknown reason'] }, count: { $sum: 1 }, cancelledBy: { $first: { $ifNull: ['$cancelledBy', 'System'] } } } },
        { $sort: { count: -1 } }, { $limit: 10 },
      ]),
      Ride.aggregate([{ $match: q }, { $group: { _id: { $ifNull: ['$cancelledBy', 'system'] }, n: { $sum: 1 } } }]),
    ])
    const cancellationReasons = stats.map((s: any) => ({ reason: s._id || 'Unknown reason', count: s.count, cancelledBy: s.cancelledBy }))
    const byCancelledBy = Object.fromEntries(by.map((x: any) => [x._id || 'system', x.n]))

    return NextResponse.json({ rides, cancellationReasons, total, page, limit, stats: { total, byCancelledBy } })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
