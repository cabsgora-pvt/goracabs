export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { maybeAutoSwitchZone } from '@/lib/zone-auto'
import { withCors, corsOptions } from '@/lib/cors'
import { sweepDueNotifications } from '@/lib/notifications'
import { sweepOverdueFaceVerification } from '@/lib/face-sweep'
import { isTeleport } from '@/lib/geo-guard'

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

    const prev: any = await Driver.findById(payload.id).select('currentLat currentLng locationUpdatedAt').lean()
    if (!prev) return withCors({ error: 'Driver not found' }, 404)
    // Teleport guard: a jump implying > MAX_KMPH since the last stored fix is
    // refused and NOT stored (spoofed GPS / a bad fix would otherwise move the
    // driver into another city's dispatch pool or zone).
    if (isTeleport(prev, la, ln)) {
      return withCors({ error: 'Location jump ignored', code: 'LOCATION_JUMP', ignored: true }, 422)
    }

    const update: any = { locationUpdatedAt: new Date(), currentLat: la, currentLng: ln }
    const h = Number(heading)
    if (heading != null && Number.isFinite(h)) update.currentHeading = ((h % 360) + 360) % 360

    await Driver.findByIdAndUpdate(payload.id, update)
    // Drivers on automatic zone follow their position (see lib/zone-auto):
    // switched only after two fixes inside the new zone >= 60 s apart.
    await maybeAutoSwitchZone(String(payload.id), la, ln).catch(() => null)
    // The foreground service keeps pinging this even if the driver force-quit
    // the app right after a verification prompt appeared — this is what
    // catches that silence instead of leaving the check pending forever.
    await sweepOverdueFaceVerification(String(payload.id))
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
