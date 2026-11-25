export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import { sweepOrphanPrepayments } from '@/lib/prepay'

// POST /api/cron/payments — money sweeps, for an external scheduler (every few
// minutes). Auth: CRON_SECRET in `x-cron-secret`, or an admin.
//   • orphan prepayments (lib/prepay sweepOrphanPrepayments): a wallet
//     prepayment no booking linked within 15 min, and a Razorpay outstation
//     prepayment (seen by the webhook) no booking linked within 30 min, go back
//     to the rider's wallet — once each, never racing a booking that links it.
export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET
  const viaSecret = !!secret && req.headers.get('x-cron-secret') === secret
  if (!viaSecret) { const denied = await guardAdmin(req); if (denied) return denied }
  await connectDB()
  const limit = Math.min(200, Math.max(1, Number(req.nextUrl.searchParams.get('limit')) || 50))
  const out = await sweepOrphanPrepayments(limit)
  return NextResponse.json({ success: true, ...out })
}
