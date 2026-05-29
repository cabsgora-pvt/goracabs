export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'

export async function GET() {
  try {
    await connectDB()
    const rides = await Ride.find({ status: 'cancelled' }).sort({ createdAt: -1 }).lean()

    const reasonStats: Record<string, { count: number; cancelledBy: string }> = {}
    rides.forEach((r: any) => {
      const reason = r.cancellationReason || 'Unknown reason'
      const by = r.cancelledBy || 'System'
      if (!reasonStats[reason]) reasonStats[reason] = { count: 0, cancelledBy: by }
      reasonStats[reason].count++
    })

    const cancellationReasons = Object.entries(reasonStats)
      .map(([reason, data]) => ({ reason, ...data }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 10)

    return NextResponse.json({ rides, cancellationReasons })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
