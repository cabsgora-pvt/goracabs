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
    const { page, limit, skip } = parsePaging(req.nextUrl.searchParams, 200)
    const q = { scheduledAt: { $exists: true, $ne: null }, status: 'pending' }
    const [rides, total] = await Promise.all([
      Ride.find(q).sort({ scheduledAt: 1 }).skip(skip).limit(limit).lean(),
      Ride.countDocuments(q),
    ])
    return NextResponse.json({ rides, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
