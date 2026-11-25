export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import { secretEquals } from '@/lib/auth'
import { sendDueNotifications } from '@/lib/notifications'

// Sends scheduled push notifications that are due. The app also does this on
// its own from busy request paths (lib/notifications.ts); this route lets an
// external scheduler make it exact. Auth: CRON_SECRET in `x-cron-secret`, or
// an admin session.
export async function POST(req: NextRequest) {
  // Constant-time: a plain === leaks how much of the secret matched.
  const viaSecret = secretEquals(req.headers.get('x-cron-secret'), process.env.CRON_SECRET)
  if (!viaSecret) { const denied = await guardAdmin(req); if (denied) return denied }
  await connectDB()
  const sent = await sendDueNotifications(50)
  return NextResponse.json({ success: true, sent })
}
