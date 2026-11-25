export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth, requireActiveDriver } from '@/lib/auth'
import { holdOf, holdMessage } from '@/lib/account-hold'
import { maybeAutoSwitchZone } from '@/lib/zone-auto'
import { isTeleport } from '@/lib/geo-guard'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { isOnline, lat, lng } = await req.json().catch(() => ({} as any))
    // Going online needs a live account (not blocked / deleted, session not
    // revoked). Going offline always works.
    if (isOnline) {
      const act = await requireActiveDriver(req)
      if (!act.ok) return withCors({ error: act.error, code: act.code }, act.status)
    }
    await connectDB()

    // A client could skip the app's own lock screen — this is the real gate.
    if (isOnline) {
      const existing: any = await Driver.findById(payload.id).select('faceVerificationRequired faceVerificationReason accountHold status').lean()
      if (existing?.accountHold?.active) {
        const hold = holdOf(existing)
        return withCors({ error: holdMessage(hold), accountHold: true, holdKind: hold.kind, holdReason: hold.reason }, 403)
      }
      if (existing?.faceVerificationRequired) {
        return withCors({
          error: 'Face verification required before going online',
          faceVerificationRequired: true,
          faceVerificationReason: existing.faceVerificationReason || 'mismatch',
        }, 403)
      }
    }

    const update: any = { isOnline: !!isOnline }
    // Stamp freshness here too. The ETA engine and dispatch both require a
    // recent locationUpdatedAt, so without this a driver who just tapped
    // "go online" stays invisible until their first 15s location push.
    // Only a real fix while going online counts. Driver app builds before
    // 1.1.2 send 0,0 when going offline, which parked the driver in the
    // Atlantic with a fresh timestamp.
    const la = Number(lat), ln = Number(lng)
    const realFix = isOnline && lat != null && lng != null && Number.isFinite(la) && Number.isFinite(ln)
      && !(la === 0 && ln === 0) && Math.abs(la) <= 90 && Math.abs(ln) <= 180
    // A fix that jumps impossibly far from the last one is not stored (going
    // online still works) — same guard as auth/driver/location.
    let jump = false
    if (realFix) {
      const prev: any = await Driver.findById(payload.id).select('currentLat currentLng locationUpdatedAt').lean()
      jump = isTeleport(prev, la, ln)
    }
    if (realFix && !jump) {
      update.currentLat = la
      update.currentLng = ln
      update.locationUpdatedAt = new Date()
    }

    const driver: any = await Driver.findByIdAndUpdate(payload.id, update, { new: true }).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    const zoneChangedTo = realFix && !jump ? await maybeAutoSwitchZone(String(driver._id), la, ln).catch(() => null) : null

    return withCors({ success: true, isOnline: driver.isOnline, ...(zoneChangedTo ? { zoneChangedTo } : {}) })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
