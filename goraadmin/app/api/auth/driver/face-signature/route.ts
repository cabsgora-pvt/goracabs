export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { uploadRef } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

// POST { embedding: number[], photoUrl: string } → save the driver's
// registration-time face signature, once. Called after the guided capture
// step in the driver app's registration flow.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { embedding, photoUrl } = await req.json()
    if (!Array.isArray(embedding) || embedding.length === 0 || embedding.some((n) => typeof n !== 'number')) {
      return withCors({ error: 'Valid embedding required' }, 400)
    }
    if (!photoUrl || typeof photoUrl !== 'string') {
      return withCors({ error: 'photoUrl required' }, 400)
    }

    if (embedding.length > 2048 || embedding.some((n: number) => !Number.isFinite(n))) {
      return withCors({ error: 'Valid embedding required' }, 400)
    }
    const photo = uploadRef(photoUrl, req)
    if (!photo) return withCors({ error: 'photoUrl must be an uploaded file (/uploads/…)' }, 400)

    await connectDB()
    const d: any = await Driver.findById(payload.id).select('status registrationStep faceSignature faceResetAllowed').lean()
    if (!d) return withCors({ error: 'Driver not found' }, 404)

    // The reference face is fixed once the registration is submitted (or the
    // driver is approved): re-enrolling a different face would hand the
    // account — and every later mid-ride face check — to someone else. An
    // admin can allow one new capture (POST /api/drivers/{id}/face-reset).
    // A driver with no face on file at all (older accounts) may enrol once.
    const hasFace = Array.isArray(d.faceSignature) && d.faceSignature.length > 0
    const locked = d.status === 'approved' || d.status === 'blocked' || d.registrationStep === 'submitted'
    if (hasFace && locked && !d.faceResetAllowed) {
      return withCors({ error: 'Your face is already registered. Contact support to reset it.', code: 'FACE_LOCKED' }, 409)
    }

    const res = await Driver.updateOne(
      // Re-check the same condition atomically and consume the admin's reset.
      hasFace && locked ? { _id: payload.id, faceResetAllowed: true } : { _id: payload.id },
      {
        $set: {
          faceSignature: embedding,
          faceReferencePhotoUrl: photo,
          faceSignatureSavedAt: new Date(),
          // The guided capture's frontal shot doubles as the driver's profile
          // picture — there is no separate gallery-picked photo anymore.
          profilePicUrl: photo,
          faceResetAllowed: false,
        },
      },
    )
    if (!res.matchedCount) return withCors({ error: 'Your face is already registered. Contact support to reset it.', code: 'FACE_LOCKED' }, 409)

    return withCors({ success: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
