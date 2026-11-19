import { NextResponse , NextRequest} from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'

// Admin pages only. It answered anyone with every matching ride and rider.
export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const rides = await Ride.find({
      scheduledAt: { $exists: true, $ne: null },
      status: 'pending',
    }).sort({ scheduledAt: 1 }).lean()
    return NextResponse.json({ rides })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
