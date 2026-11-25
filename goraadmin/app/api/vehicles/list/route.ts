import { NextResponse , NextRequest} from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

// Admin pages only. It answered anyone with every matching ride and rider.
export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const { page, limit, skip } = parsePaging(req.nextUrl.searchParams, 200)
    const q = { vehicleNumber: { $exists: true, $ne: '' }, status: { $ne: 'deleted' } }
    const [vehicles, total] = await Promise.all([
      Driver.find(q, { name: 1, vehicleNumber: 1, vehicleModel: 1, vehicleType: 1, status: 1, createdAt: 1 })
        .sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
      Driver.countDocuments(q),
    ])
    return NextResponse.json({ vehicles, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
