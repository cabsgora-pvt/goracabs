import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import SupportTicket from '@/models/SupportTicket'
import Withdrawal from '@/models/Withdrawal'
import SOSAlert, { SOS_OPEN_STATUSES } from '@/models/SOSAlert'
import AccountRequest from '@/models/AccountRequest'
import { guardAdmin } from '@/lib/admin-guard'
import { istMidnight, istMonthStart, FARE_EXPR } from '@/lib/finance'

// Days/months are India time (lib/finance.ts). Revenue and commission count
// completed rides by completedAt, and only once their payment was collected
// (paymentStatus 'paid'); completed rides awaiting payment are *Pending.

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const today = istMidnight()
    const weekAgo = istMidnight(6)
    const monthStart = istMonthStart()

    const sumRides = (match: any) => Ride.aggregate([
      { $match: match },
      {
        $group: {
          _id: null, n: { $sum: 1 },
          fare: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, FARE_EXPR, 0] } },
          commission: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, { $ifNull: ['$commissionAmount', 0] }, 0] } },
          pending: { $sum: { $cond: [{ $ne: ['$paymentStatus', 'paid'] }, FARE_EXPR, 0] } },
        },
      },
    ]).then(r => r[0] || { n: 0, fare: 0, commission: 0, pending: 0 })

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
      // Unresolved: raised and not yet closed (acknowledged ones still need help).
      SOSAlert.countDocuments({ status: { $in: SOS_OPEN_STATUSES } }),
      AccountRequest.countDocuments({ status: 'pending' }),
    ])

    const [ridesByDay, revenueByDay] = await Promise.all([
      Ride.aggregate([
        { $match: { createdAt: { $gte: weekAgo } } },
        { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: '+05:30' } }, rides: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: { status: 'completed', paymentStatus: 'paid', completedAt: { $gte: weekAgo } } },
        { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$completedAt', timezone: '+05:30' } }, revenue: { $sum: FARE_EXPR } } },
      ]),
    ])
    const days = new Map<string, { _id: string; rides: number; revenue: number }>()
    for (const d of ridesByDay) days.set(d._id, { _id: d._id, rides: d.rides, revenue: 0 })
    for (const d of revenueByDay) days.set(d._id, { _id: d._id, rides: days.get(d._id)?.rides || 0, revenue: d.revenue })
    const chartAgg = Array.from(days.values()).sort((a, b) => a._id.localeCompare(b._id))

    const serviceAgg = await Ride.aggregate([
      { $match: { status: 'completed', paymentStatus: 'paid', completedAt: { $gte: weekAgo } } },
      { $group: { _id: '$service', revenue: { $sum: FARE_EXPR }, rides: { $sum: 1 } } },
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
      todayPending: todayDone.pending,
      weekPending: weekDone.pending,
      monthPending: monthDone.pending,
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
