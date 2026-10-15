export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import FaceVerification from '@/models/FaceVerification'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { VERIFICATION_WINDOW_SEC } from '@/lib/face-match'
import { sweepOverdueFaceVerification } from '@/lib/face-sweep'

export async function OPTIONS() { return corsOptions() }

// Random point in the ride, 2-8 minutes in, that this ride's one check fires at.
function randomDueAt(from: Date): Date {
  const minMs = 2 * 60_000, maxMs = 8 * 60_000
  return new Date(from.getTime() + minMs + Math.random() * (maxMs - minMs))
}

// GET /api/rides/driver/face-check?rideId=X — polled every ~45s during an
// ongoing ride. Decides, server-side, whether this ride's one random check
// is due yet. The client cannot opt out of this by not asking: if it stops
// polling, the ride itself is still progressing on the server's clock, and
// the next poll (or the no-response sweep) catches the silence.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const rideId = req.nextUrl.searchParams.get('rideId')
    if (!rideId) return withCors({ error: 'rideId required' }, 400)

    await connectDB()
    const ride: any = await Ride.findOne({ _id: rideId, driverId: payload.id }).lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status !== 'ongoing') return withCors({ required: false })

    const now = new Date()

    // A check for this ride already fired — find it instead of scheduling a new one.
    if (ride.faceVerifyTriggered) {
      const attempt: any = await FaceVerification.findOne({ rideId, status: 'pending' }).lean()
      if (!attempt) return withCors({ required: false }) // already resolved
      if (now >= attempt.deadlineAt) {
        await sweepOverdueFaceVerification(String(payload.id))
        return withCors({ required: false, rideCancelled: true })
      }
      const deadlineSec = Math.max(1, Math.round((new Date(attempt.deadlineAt).getTime() - now.getTime()) / 1000))
      return withCors({ required: true, attemptId: attempt._id, deadlineSec })
    }

    // No due time set yet for this ride — pick one, silently.
    if (!ride.faceVerifyDueAt) {
      await Ride.findByIdAndUpdate(rideId, { faceVerifyDueAt: randomDueAt(now) })
      return withCors({ required: false })
    }

    // Not due yet.
    if (now < new Date(ride.faceVerifyDueAt)) return withCors({ required: false })

    // Due now — fire it.
    const deadlineAt = new Date(now.getTime() + VERIFICATION_WINDOW_SEC * 1000)
    const attempt = await FaceVerification.create({
      driverId: payload.id,
      rideId,
      status: 'pending',
      triggeredAt: now,
      deadlineAt,
    })
    await Ride.findByIdAndUpdate(rideId, { faceVerifyTriggered: true })

    return withCors({ required: true, attemptId: attempt._id, deadlineSec: VERIFICATION_WINDOW_SEC })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
