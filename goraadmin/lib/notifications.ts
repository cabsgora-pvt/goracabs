// ─────────────────────────────────────────────────────────────────────────────
// Admin push notifications: sending, and sending scheduled ones on time.
//
// A scheduled notification is stored with status 'scheduled' and stays out of
// both app feeds until it is sent. There is no always-on scheduler in this app,
// so — like the ride dispatch sweep — due notifications are sent
// opportunistically from requests that arrive all the time (the driver trip
// feed and location pings, both apps' notification feeds, the admin list), at
// most once every SWEEP_EVERY_MS per server process. /api/cron/notifications
// runs the same sweep for an external scheduler.
//
// Each due notification is claimed atomically (scheduled → sent) before it is
// pushed, so two requests sweeping at once never send it twice.
// ─────────────────────────────────────────────────────────────────────────────
import PushNotification from '@/models/PushNotification'
import User from '@/models/User'
import Driver from '@/models/Driver'
import { sendPushAsync } from './push'

/** Feed filter: only notifications that have actually gone out. */
export const SENT_ONLY = { status: { $nin: ['scheduled', 'cancelled'] } }

/** Earliest and latest a notification may be scheduled for. */
export const SCHEDULE_MIN_LEAD_MS = 60 * 1000
export const SCHEDULE_MAX_AHEAD_MS = 60 * 24 * 60 * 60 * 1000

const SWEEP_EVERY_MS = 30 * 1000
let lastSweep = 0

/**
 * Pushes `n` to every phone it targets and returns how many accounts it
 * reached. Deleted accounts are skipped.
 */
export async function pushToTargets(n: any): Promise<number> {
  const t = n.target
  const riderQ: any = t === 'all' || t === 'riders' ? { status: { $ne: 'deleted' } } : t === 'specific' ? { _id: n.targetUserId } : null
  const driverQ: any = t === 'all' || t === 'drivers' ? { status: { $ne: 'deleted' } } : t === 'specific' ? { _id: n.targetUserId } : null
  const [riders, drivers]: any[] = await Promise.all([
    riderQ ? User.find(riderQ).select('fcmToken').lean() : [],
    driverQ ? Driver.find(driverQ).select('fcmToken').lean() : [],
  ])
  const base = (process.env.PUBLIC_BASE_URL || 'https://goracabs.com').replace(/\/$/, '')
  const image = n.imageUrl ? (String(n.imageUrl).startsWith('/') ? base + n.imageUrl : n.imageUrl) : undefined
  for (const d of [...riders, ...drivers]) {
    if (d.fcmToken) {
      sendPushAsync(d.fcmToken, {
        title: n.title, body: n.message, imageUrl: image, channelId: 'general',
        data: { type: 'broadcast', id: String(n._id) },
      })
    }
  }
  return riders.length + drivers.length
}

/** Sends every scheduled notification that is due. Returns how many it sent. */
export async function sendDueNotifications(limit = 10): Promise<number> {
  let sent = 0
  for (let i = 0; i < limit; i++) {
    const now = new Date()
    const n: any = await PushNotification.findOneAndUpdate(
      { status: 'scheduled', scheduledAt: { $lte: now } },
      { $set: { status: 'sent', sentAt: now } },
      { sort: { scheduledAt: 1 }, new: true },
    ).lean()
    if (!n) break
    try {
      const count = await pushToTargets(n)
      await PushNotification.updateOne({ _id: n._id }, { $set: { deliveredCount: count } })
    } catch (e) {
      console.error('[notifications] scheduled send failed', String(n._id), e)
    }
    sent++
  }
  return sent
}

/** Throttled, never-throwing sweep for the hot request paths. Do not await. */
export function sweepDueNotifications(): void {
  const now = Date.now()
  if (now - lastSweep < SWEEP_EVERY_MS) return
  lastSweep = now
  sendDueNotifications().catch(e => console.error('[notifications] sweep failed', e))
}
