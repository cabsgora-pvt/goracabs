export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/driver/profile-pic  body: { url }  → update the driver's photo
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { url } = await req.json()
    if (!url) return withCors({ error: 'url required' }, 400)
    await connectDB()
    // A driver's photo is the face scanned at registration and cannot be
    // swapped for another picture (riders must see who actually drives).
    const current: any = await Driver.findById(payload.id).select('faceReferencePhotoUrl').lean()
    if (!current) return withCors({ error: 'Driver not found' }, 404)
    if (current.faceReferencePhotoUrl) {
      return withCors({ error: 'Your photo comes from your face verification and cannot be changed. Contact support if it needs updating.' }, 403)
    }
    const driver: any = await Driver.findByIdAndUpdate(payload.id, { profilePicUrl: url }, { new: true }).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, profilePicUrl: url })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
