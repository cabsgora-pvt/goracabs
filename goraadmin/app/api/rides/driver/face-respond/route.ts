export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import FaceVerification from '@/models/FaceVerification'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { cosineSimilarity, FACE_MATCH_THRESHOLD } from '@/lib/face-match'

export async function OPTIONS() { return corsOptions() }

// POST { attemptId, embedding, photoUrl } → the driver's answer to a
// mid-ride face-check. Match decision is made here, server-side, against the
// signature saved at registration — never from the device's own claim.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { attemptId, embedding, photoUrl } = await req.json()
    if (!attemptId) return withCors({ error: 'attemptId required' }, 400)
    if (!Array.isArray(embedding) || embedding.length === 0) {
      return withCors({ error: 'Valid embedding required' }, 400)
    }

    await connectDB()
    const attempt: any = await FaceVerification.findOne({ _id: attemptId, driverId: payload.id })
    if (!attempt) return withCors({ error: 'Verification attempt not found' }, 404)
    if (attempt.status !== 'pending') {
      // Already resolved (e.g. the deadline swept it as no_response just before
      // this request landed) — tell the truth about what happened instead of
      // silently overwriting it.
      return withCors({ matched: attempt.status === 'matched', alreadyResolved: true })
    }
    const now = new Date()
    if (now >= attempt.deadlineAt) {
      await FaceVerification.findByIdAndUpdate(attempt._id, { status: 'no_response', respondedAt: now })
      if (attempt.rideId) {
        await Ride.findByIdAndUpdate(attempt.rideId, {
          status: 'cancelled', cancelledBy: 'system', cancellationReason: 'face_verification_failed',
        })
      }
      await Driver.findByIdAndUpdate(payload.id, { faceVerificationRequired: true, faceVerificationReason: 'no_response' })
      return withCors({ matched: false, late: true })
    }

    const driver: any = await Driver.findById(payload.id).select('faceSignature').lean()
    if (!driver || !Array.isArray(driver.faceSignature) || driver.faceSignature.length === 0) {
      return withCors({ error: 'No face signature on file — contact support' }, 400)
    }

    const score = cosineSimilarity(embedding, driver.faceSignature)
    const matched = score >= FACE_MATCH_THRESHOLD

    await FaceVerification.findByIdAndUpdate(attempt._id, {
      status: matched ? 'matched' : 'mismatch',
      matchScore: score,
      photoUrl,
      respondedAt: now,
    })

    if (!matched) {
      if (attempt.rideId) {
        await Ride.findByIdAndUpdate(attempt.rideId, {
          status: 'cancelled', cancelledBy: 'system', cancellationReason: 'face_verification_failed',
        })
      }
      await Driver.findByIdAndUpdate(payload.id, { faceVerificationRequired: true, faceVerificationReason: 'mismatch' })
    }

    return withCors({ matched, score })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
