export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { name, email, state, zoneId, zoneName, profilePicUrl } = await req.json()
    if (!name || !state || !zoneId) return withCors({ error: 'Name, state and zone are required' }, 400)

    await connectDB()
    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      { name, email, state, zoneId, zoneName, ...(profilePicUrl && { profilePicUrl }), registrationStep: 'vehicle' },
      { new: true }
    ).lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, driver })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
