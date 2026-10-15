export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import FaceVerification from '@/models/FaceVerification'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { cosineSimilarity, FACE_MATCH_THRESHOLD, VERIFICATION_WINDOW_SEC } from '@/lib/face-match'

export async function OPTIONS() { return corsOptions() }

// POST { embedding, photoUrl } → standalone re-verify to clear a
// faceVerificationRequired lock (no active ride involved). Logged the same
// way as an in-ride check, with rideId left null, so the admin sees it too.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { embedding, photoUrl } = await req.json()
    if (!Array.isArray(embedding) || embedding.length === 0) {
      return withCors({ error: 'Valid embedding required' }, 400)
    }

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if (!Array.isArray(driver.faceSignature) || driver.faceSignature.length === 0) {
      return withCors({ error: 'No face signature on file — contact support' }, 400)
    }

    const score = cosineSimilarity(embedding, driver.faceSignature)
    const matched = score >= FACE_MATCH_THRESHOLD
    const now = new Date()

    await FaceVerification.create({
      driverId: driver._id,
      rideId: null,
      status: matched ? 'matched' : 'mismatch',
      photoUrl,
      matchScore: score,
      triggeredAt: now,
      respondedAt: now,
      deadlineAt: new Date(now.getTime() + VERIFICATION_WINDOW_SEC * 1000),
    })

    if (matched) {
      await Driver.findByIdAndUpdate(driver._id, {
        faceVerificationRequired: false,
        faceVerificationReason: null,
      })
    }

    return withCors({ matched, score })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
