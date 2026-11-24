import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import SupportTicket from '@/models/SupportTicket'
import Withdrawal from '@/models/Withdrawal'
import SOSAlert from '@/models/SOSAlert'
import AccountRequest from '@/models/AccountRequest'
import { guardAdmin } from '@/lib/admin-guard'

// Midnight India time, whatever the server's own timezone (UTC on the VPS).
const IST = 5.5 * 3600e3
const istMidnight = (daysAgo = 0) => new Date(Math.floor((Date.now() + IST) / 864e5) * 864e5 - IST - daysAgo * 864e5)

export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const today = istMidnight()
    const weekAgo = istMidnight(6)
    const monthStart = (() => { const d = new Date(Date.now() + IST); return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) - IST) })()

    const sumRides = (match: any) => Ride.aggregate([
      { $match: match },
      { $group: { _id: null, n: { $sum: 1 }, fare: { $sum: { $ifNull: ['$totalFare', '$fare'] } }, commission: { $sum: { $ifNull: ['$commissionAmount', 0] } } } },
    ]).then(r => r[0] || { n: 0, fare: 0, commission: 0 })

    const [
      totalUsers, totalDrivers, onlineDrivers, todayRides, pendingApprovals, openTickets, pendingWithdrawals, recentRides,
      todayDone, weekDone, monthDone,
      todayCancelled, liveNow, searchingNow, scheduledUpcoming,
      newRidersToday, newRidersWeek, newDriversWeek,
      heldDrivers, heldRiders, negativeWalletDrivers, owedAgg,
      openSos, pendingRequests,
    ] = await Promise.all([
      User.countDocuments({ status: { $ne: 'deleted' } }),
      Driver.countDocuments({ status: 'approved' }),
      Driver.countDocuments({ isOnline: true, status: 'approved' }),
      Ride.countDocuments({ createdAt: { $gte: today } }),
      Driver.countDocuments({ status: 'pending' }),
      SupportTicket.countDocuments({ status: 'open' }),
      Withdrawal.countDocuments({ status: 'pending' }),
      Ride.find().sort({ createdAt: -1 }).limit(10).lean(),
      sumRides({ status: 'completed', completedAt: { $gte: today } }),
      sumRides({ status: 'completed', completedAt: { $gte: weekAgo } }),
      sumRides({ status: 'completed', completedAt: { $gte: monthStart } }),
      Ride.countDocuments({ status: 'cancelled', createdAt: { $gte: today } }),
      Ride.countDocuments({ status: { $in: ['accepted', 'arrived', 'ongoing'] } }),
      Ride.countDocuments({ status: 'pending' }),
      Ride.countDocuments({ status: { $in: ['pending', 'accepted'] }, $or: [{ scheduledAt: { $gte: new Date() } }, { departureAt: { $gte: new Date() } }] }),
      User.countDocuments({ createdAt: { $gte: today } }),
      User.countDocuments({ createdAt: { $gte: weekAgo } }),
      Driver.countDocuments({ createdAt: { $gte: weekAgo } }),
      Driver.countDocuments({ $or: [{ 'accountHold.active': true }, { faceVerificationRequired: true }] }),
      User.countDocuments({ 'accountHold.active': true }),
      Driver.countDocuments({ walletBalance: { $lt: 0 }, status: { $ne: 'deleted' } }),
      Driver.aggregate([{ $match: { walletBalance: { $lt: 0 } } }, { $group: { _id: null, total: { $sum: '$walletBalance' } } }]),
      SOSAlert.countDocuments({ status: 'active' }),
      AccountRequest.countDocuments({ status: 'pending' }),
    ])

    const chartAgg = await Ride.aggregate([
      { $match: { createdAt: { $gte: weekAgo } } },
      {
        $group: {
          _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: '+05:30' } },
          rides: { $sum: 1 },
          revenue: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$totalFare', '$fare'] }, 0] } },
        },
      },
      { $sort: { _id: 1 } },
    ])

    const serviceAgg = await Ride.aggregate([
      { $match: { status: 'completed', createdAt: { $gte: weekAgo } } },
      { $group: { _id: '$service', revenue: { $sum: { $ifNull: ['$totalFare', '$fare'] } }, rides: { $sum: 1 } } },
    ])
    const todayByService = await Ride.aggregate([
      { $match: { createdAt: { $gte: today } } },
      { $group: { _id: { $ifNull: ['$service', 'taxi'] }, n: { $sum: 1 } } },
    ])

    return NextResponse.json({
      totalUsers,
      totalDrivers,
      onlineDrivers,
      todayRides,
      todayRevenue: todayDone.fare,
      todayCommission: todayDone.commission,
      todayCompleted: todayDone.n,
      todayCancelled,
      weekRevenue: weekDone.fare,
      weekCommission: weekDone.commission,
      weekCompleted: weekDone.n,
      monthRevenue: monthDone.fare,
      monthCommission: monthDone.commission,
      liveNow,
      searchingNow,
      scheduledUpcoming,
      newRidersToday,
      newRidersWeek,
      newDriversWeek,
      heldDrivers,
      heldRiders,
      negativeWalletDrivers,
      driversOwe: Math.abs(owedAgg[0]?.total || 0),
      openSos,
      pendingRequests,
      pendingApprovals,
      openTickets,
      pendingWithdrawals,
      recentRides,
      chartData: chartAgg,
      serviceData: serviceAgg.map(s => ({ service: s._id || 'taxi', revenue: s.revenue, rides: s.rides })),
      todayByService: todayByService.map(s => ({ service: s._id, rides: s.n })),
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message || 'Server error' }, { status: 500 })
  }
}
