export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// Save the driver's FCM push token so the backend can send ride alerts even
// when the app is fully closed (Layer 2). The actual send happens wherever a
// ride is assigned to a driver — see the note in that flow.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { token } = await req.json()
    if (!token || typeof token !== 'string') {
      return withCors({ error: 'Token is required' }, 400)
    }

    await connectDB()
    await Driver.findByIdAndUpdate(payload.id, { fcmToken: token })
    return withCors({ success: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
