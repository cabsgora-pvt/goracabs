import { NextResponse , NextRequest} from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'

// Admin pages only. It answered anyone with every matching ride and rider.
export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const vehicles = await Driver.find(
      { vehicleNumber: { $exists: true, $ne: '' } },
      { name: 1, vehicleNumber: 1, vehicleModel: 1, vehicleType: 1, status: 1, createdAt: 1 }
    ).sort({ createdAt: -1 }).lean()
    return NextResponse.json({ vehicles })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
