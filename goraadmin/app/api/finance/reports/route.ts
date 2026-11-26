export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { financeTotals, istRange, completedMatch, PAID, FARE_EXPR } from '@/lib/finance'

// GET ?dateFrom=YYYY-MM-DD&dateTo=YYYY-MM-DD (IST calendar days, inclusive)
// Rides count by completedAt, for totalFare, and only when the payment was
// collected (lib/finance.ts). Existing fields kept (netRevenue = commission −
// ride franchise share, as before); platformNet is Gora's whole net:
// commission + subscriptions + cancellation fees kept − both franchise shares
// − refunds on completed rides.
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const { searchParams } = new URL(req.url)
    const range = istRange(searchParams.get('dateFrom'), searchParams.get('dateTo'))
    // ?zoneId= scopes every figure to one zone (lib/finance financeTotals opts).
    const zoneId = searchParams.get('zoneId') || ''
    if (zoneId && !mongoose.isValidObjectId(zoneId)) return NextResponse.json({ error: 'Invalid zone' }, { status: 400 })
    const paidMatch = completedMatch(range, { ...PAID, ...(zoneId ? { zoneId: new mongoose.Types.ObjectId(zoneId) } : {}) })

    const [t, byService, byPayment, topDrivers] = await Promise.all([
      financeTotals(range, { zoneId: zoneId || undefined }),
      Ride.aggregate([
        { $match: paidMatch },
        { $group: { _id: '$service', revenue: { $sum: FARE_EXPR }, count: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: paidMatch },
        { $group: { _id: '$paymentMode', revenue: { $sum: FARE_EXPR }, count: { $sum: 1 } } },
      ]),
      Ride.aggregate([
        { $match: paidMatch },
        { $group: { _id: '$driverId', driverName: { $first: '$driverName' }, totalEarnings: { $sum: { $ifNull: ['$driverEarning', 0] } }, revenue: { $sum: FARE_EXPR }, totalRides: { $sum: 1 } } },
        { $sort: { totalEarnings: -1 } },
        { $limit: 5 },
      ]),
    ])

    const commission = Math.round(t.commission)
    const franchiseShare = Math.round(t.rideFranchiseShare)
    return NextResponse.json({
      grossRevenue: t.collectedRevenue,
      totalRides: t.collectedRides,
      commission,
      driverPayout: t.driverPayout,
      franchiseShare,
      netRevenue: commission - franchiseShare,   // ride commission net of zone-admin share (unchanged meaning)
      byService: byService.map(s => ({ service: s._id, revenue: s.revenue, count: s.count })),
      byPayment: byPayment.map(p => ({ mode: p._id, revenue: p.revenue, count: p.count })),
      topDrivers,
      // added
      completedRides: t.completedRides,
      bookedRevenue: t.bookedRevenue,
      pendingRevenue: t.pendingRevenue,
      pendingRides: t.pendingRides,
      pendingOnlineRevenue: t.pendingOnlineRevenue,
      pendingOnlineRides: t.pendingOnlineRides,
      subscriptionRevenue: t.subscriptionRevenue,
      subscriptionCount: t.subscriptionCount,
      subscriptionFranchiseShare: t.subscriptionFranchiseShare,
      cancellationFeesCollected: t.cancellationFeesCollected,
      cancellationFeesCharged: t.cancellationFeesCharged,
      refunds: t.refunds,
      refundsOnCompletedRides: t.refundsOnCompletedRides,
      couponCost: t.couponCost,               // Gora-funded coupons on paid rides (already off netCollectedRevenue and platformNet)
      netCollectedRevenue: t.netCollectedRevenue,
      platformNet: t.platformNet,               // + subscriptions + cancellation fees kept − their franchise share − refunds on completed rides
      range: { from: range.from || null, to: range.to || null, timezone: 'Asia/Kolkata' },
      zoneId: zoneId || null,
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
