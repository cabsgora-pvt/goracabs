export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

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

    await connectDB()
    await Driver.findByIdAndUpdate(payload.id, {
      faceSignature: embedding,
      faceReferencePhotoUrl: photoUrl,
      faceSignatureSavedAt: new Date(),
      // The guided capture's frontal shot doubles as the driver's profile
      // picture — there is no separate gallery-picked photo anymore.
      profilePicUrl: photoUrl,
    })

    return withCors({ success: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
