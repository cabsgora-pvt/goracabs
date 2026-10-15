export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { isOnline, lat, lng } = await req.json()
    await connectDB()

    // A client could skip the app's own lock screen — this is the real gate.
    if (isOnline) {
      const existing: any = await Driver.findById(payload.id).select('faceVerificationRequired faceVerificationReason').lean()
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
    if (lat != null) { update.currentLat = lat; update.locationUpdatedAt = new Date() }
    if (lng != null) update.currentLng = lng

    const driver: any = await Driver.findByIdAndUpdate(payload.id, update, { new: true }).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    return withCors({ success: true, isOnline: driver.isOnline })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
