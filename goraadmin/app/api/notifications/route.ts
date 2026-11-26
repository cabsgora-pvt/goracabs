import { NextRequest, NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { connectDB } from '@/lib/mongodb'
import PushNotification from '@/models/PushNotification'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import mongoose from 'mongoose'
import { pushToTargets, sendDueNotifications, countRecipients, ZONE_RIDER_DAYS, SCHEDULE_MIN_LEAD_MS, SCHEDULE_MAX_AHEAD_MS } from '@/lib/notifications'

const TARGETS = ['all', 'riders', 'drivers', 'specific', 'zone_riders', 'zone_drivers']

/** Resolve "specific" by phone and check a zone target's zone. */
async function resolveTarget(b: any): Promise<{ error?: string; status?: number; target: string; targetUserId: string; zoneId: string; zoneName: string }> {
  const target = TARGETS.includes(b.target) ? b.target : 'all'
  let targetUserId = String(b.targetUserId || '')
  let zoneId = '', zoneName = ''
  if (target === 'specific' && !targetUserId && b.targetPhone) {
    const phone = String(b.targetPhone).replace(/\D/g, '').slice(-10)
    const hit: any = (await User.findOne({ phone }).select('_id').lean()) || (await Driver.findOne({ phone }).select('_id').lean())
    if (!hit) return { error: 'No rider or driver with that phone number', status: 404, target, targetUserId, zoneId, zoneName }
    targetUserId = String(hit._id)
  }
  if (target === 'zone_riders' || target === 'zone_drivers') {
    zoneId = String(b.zoneId || '')
    const z: any = mongoose.isValidObjectId(zoneId) ? await Zone.findById(zoneId).select('name').lean() : null
    if (!z) return { error: 'Choose the zone to send it to', status: 400, target, targetUserId, zoneId, zoneName }
    zoneName = z.name || ''
  }
  return { target, targetUserId, zoneId, zoneName }
}
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

// Admin-only: returns every notification, including ones targeted at a named
// user, so it must not be reachable from an app. Drivers read their own feed
// from /api/auth/driver/notifications, riders from /api/auth/user/notifications.
// GET ?count=1&target=&targetPhone=&zoneId= — how many accounts a
// notification would reach (and how many have push on), for the admin's
// confirmation. Sends nothing.
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const sp = req.nextUrl.searchParams
    if (sp.get('count') === '1') {
      const r = await resolveTarget({ target: sp.get('target'), targetPhone: sp.get('targetPhone'), targetUserId: sp.get('targetUserId'), zoneId: sp.get('zoneId') })
      if (r.error) return NextResponse.json({ error: r.error }, { status: r.status || 400 })
      if (r.target === 'specific' && !/^[a-f0-9]{24}$/i.test(r.targetUserId)) return NextResponse.json({ error: 'Choose who to send it to' }, { status: 400 })
      const c = await countRecipients(r)
      return NextResponse.json({ ...c, target: r.target, zoneName: r.zoneName, zoneRiderDays: ZONE_RIDER_DAYS })
    }
    // Anything already due goes out before the list is shown.
    await sendDueNotifications().catch(() => 0)
    const notifications = await PushNotification.find().select('-targetUserIds').sort({ createdAt: -1 }).limit(100).lean()
    return NextResponse.json({ notifications })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

// POST { title, message, target, targetUserId?, targetPhone?, zoneId?, imageUrl?, scheduledAt? }
// target: all | riders | drivers | specific | zone_riders | zone_drivers
// (zone_*: riders with a ride in that zone in the last 90 days / drivers of
// that zone; needs zoneId).
// Without scheduledAt it is saved to the in-app feeds and pushed right away to
// every targeted phone registered for push. With scheduledAt (ISO time, 1 min
// to 60 days ahead) it is stored as 'scheduled', stays out of the feeds, and is
// sent when due (lib/notifications.ts). deliveredCount is the number of
// accounts it reached.
export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'notification.create', undefined)
    await connectDB()
    const body = await req.json()
    const { title, message } = body
    // "Specific user" can be picked by phone number (rider or driver).
    const resolved = await resolveTarget(body)
    if (resolved.error) return NextResponse.json({ error: resolved.error }, { status: resolved.status || 400 })
    const { targetUserId, zoneId, zoneName } = resolved
    if (!title || !message) {
      return NextResponse.json({ error: 'Title and message are required' }, { status: 400 })
    }
    const imageUrl = typeof body.imageUrl === 'string' ? body.imageUrl.trim().slice(0, 500) : ''
    if (imageUrl && !/^(https?:\/\/|\/uploads\/)/.test(imageUrl)) {
      return NextResponse.json({ error: 'Image must be an uploaded file or an https link' }, { status: 400 })
    }

    let scheduledAt: Date | null = null
    if (body.scheduledAt) {
      const at = new Date(body.scheduledAt)
      const ahead = at.getTime() - Date.now()
      if (Number.isNaN(at.getTime())) return NextResponse.json({ error: 'Choose a valid date and time' }, { status: 400 })
      if (ahead < SCHEDULE_MIN_LEAD_MS) return NextResponse.json({ error: 'Schedule it at least 1 minute from now' }, { status: 400 })
      if (ahead > SCHEDULE_MAX_AHEAD_MS) return NextResponse.json({ error: 'Schedule it within the next 60 days' }, { status: 400 })
      scheduledAt = at
    }

    const targetLabels: Record<string, string> = {
      all: 'All Users',
      riders: 'All Riders',
      drivers: 'All Drivers',
      specific: 'Specific User',
      zone_riders: `Riders in ${zoneName}`,
      zone_drivers: `Drivers in ${zoneName}`,
    }
    const t = resolved.target
    const valid = (id: string) => /^[a-f0-9]{24}$/i.test(String(id || ''))
    if (t === 'specific' && !valid(targetUserId)) {
      return NextResponse.json({ error: 'Choose who to send it to' }, { status: 400 })
    }

    if (scheduledAt) {
      const notification = await PushNotification.create({
        title, message, target: t, targetUserId: targetUserId || '', imageUrl, zoneId, zoneName,
        status: 'scheduled', scheduledAt, sentAt: null, deliveredCount: 0,
      })
      return NextResponse.json({
        success: true, scheduled: true, notification: notification.toObject(), targetLabel: targetLabels[t] || t,
      }, { status: 201 })
    }

    const notification = await PushNotification.create({
      title, message, target: t, targetUserId: targetUserId || '', imageUrl, zoneId, zoneName,
      status: 'sent', sentAt: new Date(), deliveredCount: 0,
    })
    const deliveredCount = await pushToTargets(notification.toObject())
    await PushNotification.updateOne({ _id: notification._id }, { $set: { deliveredCount } })

    return NextResponse.json({
      success: true,
      notification: { ...notification.toObject(), deliveredCount },
      targetLabel: targetLabels[t] || t,
    }, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

// DELETE ?id= → cancels a notification that is still scheduled. One already
// sent cannot be taken back from phones, so it is refused.
export async function DELETE(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const id = req.nextUrl.searchParams.get('id') || ''
    if (!/^[a-f0-9]{24}$/i.test(id)) return NextResponse.json({ error: 'Invalid id' }, { status: 400 })
    const n = await PushNotification.findOneAndUpdate(
      { _id: id, status: 'scheduled' },
      { $set: { status: 'cancelled' } },
      { new: true },
    ).lean()
    if (!n) return NextResponse.json({ error: 'Only a notification that is still scheduled can be cancelled' }, { status: 409 })
    return NextResponse.json({ success: true, notification: n })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
