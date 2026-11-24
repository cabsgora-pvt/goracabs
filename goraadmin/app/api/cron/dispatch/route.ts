export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import { sweepExpiredOffers, activateScheduledRides, expireUnmatchedRides } from '@/lib/dispatch'
import { sweepAllOverdueFaceVerification } from '@/lib/face-sweep'

// POST /api/cron/dispatch — the dispatch sweeps, for an external scheduler
// (e.g. every 15–30 s). Auth: CRON_SECRET in `x-cron-secret`, or an admin.
//   • lapsed offers move to the next captain (sweepExpiredOffers, which first
//     closes overdue "No driver found" rides and retries unfinished refunds)
//   • scheduled rides due within 30 min start their offer ladder
//   • every driver's overdue mid-ride face checks are resolved
// The same sweeps also run opportunistically (throttled) from the driver feed.
export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET
  const viaSecret = !!secret && req.headers.get('x-cron-secret') === secret
  if (!viaSecret) { const denied = guardAdmin(req); if (denied) return denied }
  await connectDB()
  const out: Record<string, number | string> = {}
  const run = async (k: string, f: () => Promise<number>) => {
    try { out[k] = await f() } catch (e: any) { out[k] = 'error: ' + (e?.message || e) }
  }
  await run('expired', () => expireUnmatchedRides(50))
  await run('reoffered', () => sweepExpiredOffers(50))
  await run('scheduledStarted', () => activateScheduledRides(50))
  await run('faceLocked', () => sweepAllOverdueFaceVerification(100))
  return NextResponse.json({ success: true, ...out })
}
