import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import SupportTicket from '@/models/SupportTicket'
import Withdrawal from '@/models/Withdrawal'

export async function GET() {
  try {
    await connectDB()
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    const [
      totalUsers,
      totalDrivers,
      onlineDrivers,
      todayRides,
      pendingApprovals,
      openTickets,
      pendingWithdrawals,
      recentRides,
    ] = await Promise.all([
      User.countDocuments(),
      Driver.countDocuments({ status: 'approved' }),
      Driver.countDocuments({ isOnline: true }),
      Ride.countDocuments({ createdAt: { $gte: today } }),
      Driver.countDocuments({ status: 'pending' }),
      SupportTicket.countDocuments({ status: 'open' }),
      Withdrawal.countDocuments({ status: 'pending' }),
      Ride.find().sort({ createdAt: -1 }).limit(10).lean(),
    ])

    const todayRevenueAgg = await Ride.aggregate([
      { $match: { status: 'completed', createdAt: { $gte: today } } },
      { $group: { _id: null, total: { $sum: '$fare' } } },
    ])
    const todayRevenue = todayRevenueAgg[0]?.total || 0

    const sevenDaysAgo = new Date()
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)
    const chartAgg = await Ride.aggregate([
      { $match: { createdAt: { $gte: sevenDaysAgo } } },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } },
          rides: { $sum: 1 },
          revenue: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, '$fare', 0] } },
        },
      },
      { $sort: { _id: 1 } },
    ])

    const serviceAgg = await Ride.aggregate([
      { $match: { status: 'completed', createdAt: { $gte: sevenDaysAgo } } },
      { $group: { _id: '$service', revenue: { $sum: '$fare' } } },
    ])

    return NextResponse.json({
      totalUsers,
      totalDrivers,
      onlineDrivers,
      todayRides,
      todayRevenue,
      pendingApprovals,
      openTickets,
      pendingWithdrawals,
      recentRides,
      chartData: chartAgg,
      serviceData: serviceAgg.map(s => ({ service: s._id, revenue: s.revenue })),
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message || 'Server error' }, { status: 500 })
  }
}
