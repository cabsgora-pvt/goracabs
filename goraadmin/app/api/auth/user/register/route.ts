import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { name, city, email, idNumber, profilePicUrl } = await req.json()

    await connectDB()

    const user = await User.findByIdAndUpdate(
      payload.id,
      { name, email, city, idNumber, profilePicUrl, status: 'active' },
      { new: true }
    ).lean()

    if (!user) return withCors({ error: 'User not found' }, 404)

    return withCors({ success: true, user })
  } catch {
    return withCors({ error: 'Registration failed' }, 500)
  }
}
