import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const user = await User.findById(payload.id).lean()
    if (!user) return withCors({ error: 'User not found' }, 404)

    return withCors({ user })
  } catch {
    return withCors({ error: 'Failed to fetch profile' }, 500)
  }
}
