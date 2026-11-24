export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import { financeTotals, istMidnight, istMonthStart } from '@/lib/finance'

// GET → finance summary (all time + today + this month, IST).
// Revenue, commission and payout count only rides whose payment was collected
// (lib/finance.ts); completed rides still awaiting an online payment are in
// pending*. Existing fields kept: totalRides, grossRevenue, totalCommission,
// totalDriverPayout, todayCommission, todayRevenue.
export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()

    const [all, today, month] = await Promise.all([
      financeTotals(),
      financeTotals({ from: istMidnight() }),
      financeTotals({ from: istMonthStart() }),
    ])

    return NextResponse.json({
      totalRides: all.completedRides,
      grossRevenue: all.collectedRevenue,
      totalCommission: all.commission,   // ADMIN PROFIT (before franchise share)
      totalDriverPayout: all.driverPayout,
      todayCommission: today.commission,
      todayRevenue: today.collectedRevenue,
      // added
      bookedRevenue: all.bookedRevenue,
      pendingRevenue: all.pendingRevenue,
      pendingRides: all.pendingRides,
      pendingOnlineRevenue: all.pendingOnlineRevenue,
      pendingOnlineRides: all.pendingOnlineRides,
      franchiseShare: all.rideFranchiseShare,
      subscriptionRevenue: all.subscriptionRevenue,
      subscriptionFranchiseShare: all.subscriptionFranchiseShare,
      cancellationFeesCollected: all.cancellationFeesCollected,
      refunds: all.refunds,
      refundsOnCompletedRides: all.refundsOnCompletedRides,
      netCollectedRevenue: all.netCollectedRevenue,
      platformNet: all.platformNet,
      today,
      month,
      timezone: 'Asia/Kolkata',
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
