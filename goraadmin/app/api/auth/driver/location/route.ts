export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { maybeAutoSwitchZone } from '@/lib/zone-auto'
import { withCors, corsOptions } from '@/lib/cors'
import { sweepDueNotifications } from '@/lib/notifications'
import { sweepOverdueFaceVerification } from '@/lib/face-sweep'
import { isTeleport, tooSoonToStore, GEO_GUARD } from '@/lib/geo-guard'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { lat, lng, heading } = await req.json().catch(() => ({}))
    // A real fix only: numbers in range, not the 0,0 an app sends with no GPS.
    const la = Number(lat), ln = Number(lng)
    if (lat == null || lng == null || !Number.isFinite(la) || !Number.isFinite(ln)
        || Math.abs(la) > 90 || Math.abs(ln) > 180 || (la === 0 && ln === 0)) {
      return withCors({ error: 'Invalid location', code: 'INVALID_LOCATION' }, 400)
    }
    await connectDB()
    sweepDueNotifications()   // scheduled admin notifications that are due

    const prev: any = await Driver.findById(payload.id).select('currentLat currentLng locationUpdatedAt zoneAuto zoneId zoneName zoneAutoCandidate').lean()
    if (!prev) return withCors({ error: 'Driver not found' }, 404)
    // At most one stored fix per driver per STORE_EVERY_MS: extra pings are
    // acknowledged and dropped (they also cannot be used to step the speed check).
    if (tooSoonToStore(prev)) return withCors({ success: true, throttled: true })
    // Teleport guard: a move faster than MAX_KMPH from the last stored fix (every
    // move, with a minimum elapsed time — no 1 km free step any more) is refused
    // and NOT stored (spoofed GPS / a bad fix would otherwise move the driver
    // into another city's dispatch pool or zone).
    if (isTeleport(prev, la, ln)) {
      return withCors({ error: 'Location jump ignored', code: 'LOCATION_JUMP', ignored: true }, 422)
    }

    const update: any = { locationUpdatedAt: new Date(), currentLat: la, currentLng: ln }
    const h = Number(heading)
    if (heading != null && Number.isFinite(h)) update.currentHeading = ((h % 360) + 360) % 360

    // Atomic on the throttle too, so two parallel pings cannot both be stored.
    const stored = await Driver.updateOne(
      { _id: payload.id, $or: [{ locationUpdatedAt: null }, { locationUpdatedAt: { $lte: new Date(Date.now() - GEO_GUARD.STORE_EVERY_MS) } }, { locationUpdatedAt: { $gt: new Date() } }] },
      { $set: update },
    )
    if (!stored.matchedCount) return withCors({ success: true, throttled: true })
    // Drivers on automatic zone follow their position (see lib/zone-auto):
    // switched only after fixes inside the new zone spanning >= 5 min (lib/zone-auto).
    await maybeAutoSwitchZone(String(payload.id), la, ln, prev).catch(() => null)
    // The foreground service keeps pinging this even if the driver force-quit
    // the app right after a verification prompt appeared — this is what
    // catches that silence instead of leaving the check pending forever.
    await sweepOverdueFaceVerification(String(payload.id))
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
