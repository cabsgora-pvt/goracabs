export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'

// GET → finance summary: rides, gross revenue, admin commission profit, driver payout
export async function GET() {
  try {
    await connectDB()

    const startOfDay = new Date()
    startOfDay.setHours(0, 0, 0, 0)

    const [allAgg, todayAgg] = await Promise.all([
      Ride.aggregate([
        { $match: { status: 'completed' } },
        {
          $group: {
            _id: null,
            totalRides: { $sum: 1 },
            grossRevenue: { $sum: { $ifNull: ['$totalFare', '$fare'] } },
            totalCommission: { $sum: { $ifNull: ['$commissionAmount', 0] } },
            totalDriverPayout: { $sum: { $ifNull: ['$driverEarning', 0] } },
          },
        },
      ]),
      Ride.aggregate([
        { $match: { status: 'completed', completedAt: { $gte: startOfDay } } },
        {
          $group: {
            _id: null,
            todayCommission: { $sum: { $ifNull: ['$commissionAmount', 0] } },
            todayRevenue: { $sum: { $ifNull: ['$totalFare', '$fare'] } },
          },
        },
      ]),
    ])

    const a = allAgg[0] || {}
    const t = todayAgg[0] || {}

    return NextResponse.json({
      totalRides: a.totalRides || 0,
      grossRevenue: a.grossRevenue || 0,
      totalCommission: a.totalCommission || 0,   // ADMIN PROFIT
      totalDriverPayout: a.totalDriverPayout || 0,
      todayCommission: t.todayCommission || 0,
      todayRevenue: t.todayRevenue || 0,
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
