import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'

export async function GET(req: NextRequest) {
  try {
    await connectDB()
    const { searchParams } = new URL(req.url)
    const dateFrom = searchParams.get('dateFrom') || ''
    const dateTo = searchParams.get('dateTo') || ''

    const match: any = { status: 'completed' }
    if (dateFrom || dateTo) {
      match.createdAt = {}
      if (dateFrom) match.createdAt.$gte = new Date(dateFrom)
      if (dateTo) {
        const to = new Date(dateTo)
        to.setHours(23, 59, 59, 999)
        match.createdAt.$lte = to
      }
    }

    const [grossAgg, byService, byPayment, topDrivers] = await Promise.all([
      Ride.aggregate([
        { $match: match },
        { $group: { _id: null, total: { $sum: '$fare' }, count: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: match },
        { $group: { _id: '$service', revenue: { $sum: '$fare' }, count: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: match },
        { $group: { _id: '$paymentMode', revenue: { $sum: '$fare' }, count: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: match },
        { $group: { _id: '$driverId', driverName: { $first: '$driverName' }, totalEarnings: { $sum: '$fare' }, totalRides: { $sum: 1 } } },
        { $sort: { totalEarnings: -1 } },
        { $limit: 5 },
      ]),
    ])

    const grossRevenue = grossAgg[0]?.total || 0
    const totalRides = grossAgg[0]?.count || 0
    const commissionPercent = 20
    const commission = Math.round(grossRevenue * (commissionPercent / 100))
    const driverPayout = grossRevenue - commission

    return NextResponse.json({
      grossRevenue,
      totalRides,
      commission,
      driverPayout,
      netRevenue: commission,
      byService: byService.map(s => ({ service: s._id, revenue: s.revenue, count: s.count })),
      byPayment: byPayment.map(p => ({ mode: p._id, revenue: p.revenue, count: p.count })),
      topDrivers,
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
