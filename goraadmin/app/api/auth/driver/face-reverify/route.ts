export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import FaceVerification from '@/models/FaceVerification'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { cosineSimilarity, FACE_MATCH_THRESHOLD, VERIFICATION_WINDOW_SEC } from '@/lib/face-match'
import { uploadRef } from '@/lib/ride-view'
import { limitHit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

const REVERIFY_RATE = { LIMIT: 5, WINDOW_MS: 60 * 60_000 }
/** Locks the system sets itself (face-respond / face-sweep). Any other reason was an admin's. */
const SELF_CLEARABLE = ['mismatch', 'no_response']

// POST { embedding, photoUrl } → standalone re-verify to clear a
// faceVerificationRequired lock (no active ride involved). Logged the same
// way as an in-ride check, with rideId left null, so the admin sees it too.
//   ← { matched, cleared, adminHold? }   (the similarity score is NOT returned —
//     it was an oracle for tuning a spoof against the threshold)
// photoUrl must be an /uploads/ file on this server (400 PHOTO_REQUIRED).
// A match only clears a lock the system set (mismatch / no_response): a lock or
// account hold an admin imposed stays until an admin lifts it.
// 5 attempts per hour per driver (429 RATE_LIMITED).
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { embedding, photoUrl } = await req.json().catch(() => ({} as any))
    if (!Array.isArray(embedding) || embedding.length === 0 || embedding.length > 4096
        || !embedding.every((x: any) => typeof x === 'number' && Number.isFinite(x))) {
      return withCors({ error: 'Valid embedding required' }, 400)
    }
    const photo = uploadRef(photoUrl, req)
    if (!photo) return withCors({ error: 'A photo from this app is required', code: 'PHOTO_REQUIRED' }, 400)
    if (!(await limitHit(`face-reverify:${payload.id}`, REVERIFY_RATE.LIMIT, REVERIFY_RATE.WINDOW_MS))) {
      return withCors({ error: 'Too many attempts. Please try again later or contact support.', code: 'RATE_LIMITED' }, 429)
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
      photoUrl: photo,
      matchScore: score,        // kept for the admin only
      triggeredAt: now,
      respondedAt: now,
      deadlineAt: new Date(now.getTime() + VERIFICATION_WINDOW_SEC * 1000),
    })

    const adminHold = !!driver.accountHold?.active
      || (!!driver.faceVerificationRequired && !SELF_CLEARABLE.includes(String(driver.faceVerificationReason || '')))
    let cleared = false
    if (matched && driver.faceVerificationRequired && !adminHold) {
      const res = await Driver.updateOne(
        { _id: driver._id, faceVerificationRequired: true, faceVerificationReason: { $in: SELF_CLEARABLE } },
        { $set: { faceVerificationRequired: false, faceVerificationReason: null } },
      )
      cleared = res.modifiedCount > 0
    }

    return withCors({ matched, cleared, ...(adminHold ? { adminHold: true } : {}) })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
