export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import PushNotification from '@/models/PushNotification'
import { SENT_ONLY, sweepDueNotifications } from '@/lib/notifications'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → notifications this driver should see.
//
// The driver app's notification screen was served entirely by
// MockNotificationService, so drivers saw invented messages while anything
// admin actually broadcast went nowhere. This is the real feed.
//
// Note the admin route (/api/notifications) returns EVERY notification
// including ones targeted at a named user, so it is not usable from an app —
// hence a driver-scoped route rather than reusing it.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    sweepDueNotifications()
    const driverId = String((payload as any).id)

    const rows: any[] = await PushNotification.find({
      ...SENT_ONLY,
      $or: [
        { target: 'all' },
        { target: 'drivers' },
        { target: 'specific', targetUserId: driverId },
        // Sent to the drivers of a zone (lib/notifications): the ids it went to.
        { target: 'zone_drivers', targetUserIds: driverId },
      ],
    })
      .sort({ sentAt: -1 })
      .limit(50)
      .lean()

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
