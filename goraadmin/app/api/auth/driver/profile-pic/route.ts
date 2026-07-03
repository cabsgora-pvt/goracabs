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
    const driver: any = await Driver.findByIdAndUpdate(payload.id, { profilePicUrl: url }, { new: true }).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, profilePicUrl: url })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
