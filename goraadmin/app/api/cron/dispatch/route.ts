export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import { secretEquals } from '@/lib/auth'
import { sweepExpiredOffers, activateScheduledRides, expireUnmatchedRides, sweepStuckRides, sweepDriverCancels } from '@/lib/dispatch'
import { sweepAllOverdueFaceVerification } from '@/lib/face-sweep'
import { sweepOrphanPrepayments } from '@/lib/prepay'

// POST /api/cron/dispatch — the dispatch sweeps, for an external scheduler
// (e.g. every 15–30 s). Auth: CRON_SECRET in `x-cron-secret`, or an admin.
//   • lapsed offers move to the next captain (sweepExpiredOffers, which first
//     closes overdue "No driver found" rides and retries unfinished refunds)
//   • scheduled rides due within 30 min start their offer ladder
//   • every driver's overdue mid-ride face checks are resolved
//   • stuck active rides (no driver location for 20 min, or 3 h past their
//     expected end) are flagged needsReview for an admin (`stuck`)
//   • driver cancels are counted, mid-trip ones flagged (`driverCancels`)
// scripts/cron-ping.js calls this 4x a minute (every 15 s).
// The same sweeps also run opportunistically (throttled) from the driver feed.
export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET
  const viaSecret = !!secret && secretEquals(req.headers.get('x-cron-secret'), secret)
  if (!viaSecret) { const denied = await guardAdmin(req); if (denied) return denied }
  await connectDB()
  const out: Record<string, number | string> = {}
  const run = async (k: string, f: () => Promise<number>) => {
    try { out[k] = await f() } catch (e: any) { out[k] = 'error: ' + (e?.message || e) }
  }
  await run('expired', () => expireUnmatchedRides(50))
  await run('reoffered', () => sweepExpiredOffers(50))
  await run('scheduledStarted', () => activateScheduledRides(50))
  await run('faceLocked', () => sweepAllOverdueFaceVerification(100))
  await run('stuck', () => sweepStuckRides(300))
  await run('driverCancels', () => sweepDriverCancels(50))
  // Prepayments captured but never tied to a ride (lib/prepay).
  await run('orphanPrepayments', async () => { const o = await sweepOrphanPrepayments(50); return (o.walletRefunded || 0) + (o.onlineRefunded || 0) + (o.linked || 0) })
  return NextResponse.json({ success: true, ...out })
}
