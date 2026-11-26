export const dynamic = 'force-dynamic'
import { NextResponse , NextRequest} from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Admin pages only. It answered anyone with every matching ride and rider.
//
// GET ?page&limit&status&date&search → { rides, total, page, limit, stats }
//   Scheduled bookings not yet under way, soonest first: still looking for a
//   driver (pending), or taken by one (accepted) and due from 2 h ago on.
//   status: 'pending' (unassigned) | 'accepted' | 'all' (default).
//   date: an IST calendar day (YYYY-MM-DD) on scheduledAt.
//   stats (whole filter, not just the page): { unassigned, dueSoon (unassigned,
//   due within 30 min or overdue), dueIn2h (unassigned, 30 min – 2 h) }.
export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 200)
    const now = Date.now()
    const status = sp.get('status') || 'all'
    const pending = { status: 'pending' }
    const accepted = { status: 'accepted', scheduledAt: { $gte: new Date(now - 2 * 3600e3) } }
    const q: any = { scheduledAt: { $exists: true, $ne: null } }
    const and: any[] = [status === 'pending' ? pending : status === 'accepted' ? accepted : { $or: [pending, accepted] }]
    const date = (sp.get('date') || '').trim()
    if (date) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return NextResponse.json({ error: 'date must be YYYY-MM-DD' }, { status: 400 })
      and.push({ scheduledAt: { $gte: new Date(`${date}T00:00:00.000+05:30`), $lte: new Date(`${date}T23:59:59.999+05:30`) } })
    }
    const search = escapeRegex((sp.get('search') || '').trim())
    if (search) {
      const rx = { $regex: search, $options: 'i' }
      and.push({ $or: [{ riderName: rx }, { driverName: rx }, { riderPhone: rx }, { pickupAddress: rx }, { dropAddress: rx },
        ...(/^[a-f0-9]{24}$/i.test(search) ? [{ _id: new mongoose.Types.ObjectId(search) }] : [])] })
    }
    q.$and = and
    const unassigned = { ...q, $and: [...and, { status: 'pending' }] }
    const [rides, total, nUnassigned, dueSoon, dueIn2h] = await Promise.all([
      Ride.find(q).sort({ scheduledAt: 1 }).skip(skip).limit(limit).select('-messages -routePolyline -offeredHistory -rejectedBy').lean(),
      Ride.countDocuments(q),
      Ride.countDocuments(unassigned),
      Ride.countDocuments({ ...unassigned, $and: [...unassigned.$and, { scheduledAt: { $lte: new Date(now + 30 * 60e3) } }] }),
      Ride.countDocuments({ ...unassigned, $and: [...unassigned.$and, { scheduledAt: { $gt: new Date(now + 30 * 60e3), $lte: new Date(now + 2 * 3600e3) } }] }),
    ])
    return NextResponse.json({ rides, total, page, limit, stats: { unassigned: nUnassigned, dueSoon, dueIn2h }, at: new Date() })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
