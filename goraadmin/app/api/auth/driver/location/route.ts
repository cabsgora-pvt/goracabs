export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { maybeAutoSwitchZone } from '@/lib/zone-auto'
import { withCors, corsOptions } from '@/lib/cors'
import { sweepDueNotifications } from '@/lib/notifications'
import { sweepOverdueFaceVerification } from '@/lib/face-sweep'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { lat, lng, heading } = await req.json()
    await connectDB()
    sweepDueNotifications()   // scheduled admin notifications that are due

    const update: any = { locationUpdatedAt: new Date() }
    if (lat != null) update.currentLat = lat
    if (lng != null) update.currentLng = lng
    if (heading != null) update.currentHeading = heading

    await Driver.findByIdAndUpdate(payload.id, update)
    // Drivers on automatic zone follow their position (see lib/zone-auto).
    if (lat != null && lng != null) await maybeAutoSwitchZone(String(payload.id), Number(lat), Number(lng)).catch(() => null)
    // The foreground service keeps pinging this even if the driver force-quit
    // the app right after a verification prompt appeared — this is what
    // catches that silence instead of leaving the check pending forever.
    await sweepOverdueFaceVerification(String(payload.id))
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
