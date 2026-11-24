export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import PushNotification from '@/models/PushNotification'
import { SENT_ONLY, sweepDueNotifications } from '@/lib/notifications'
import { requireAuth, isAdminPayload } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → the rider's notification feed: broadcasts to everyone / all riders, and
// ones sent to this rider by name. Newest first.
export async function GET(req: NextRequest) {
  try {
    const p: any = requireAuth(req)
    if (!p?.id || isAdminPayload(p) || p.type === 'driver') return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    sweepDueNotifications()
    const rows: any[] = await PushNotification.find({
      ...SENT_ONLY,
      $or: [{ target: 'all' }, { target: 'riders' }, { target: 'specific', targetUserId: String(p.id) }],
    }).sort({ sentAt: -1 }).limit(50).lean()
    return withCors({
      notifications: rows.map(n => ({
        id: String(n._id),
        title: n.title || '',
        body: n.message || '',
        imageUrl: n.imageUrl || '',
        sentAt: n.sentAt || n.createdAt || null,
        type: n.target === 'specific' ? 'personal' : 'broadcast',
      })),
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
