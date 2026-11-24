import { holdOf, holdMessage } from '@/lib/account-hold'
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
    // A deleted account is signed out on its next call.
    if ((user as any).status === 'deleted') return withCors({ error: 'Unauthorized', accountDeleted: true }, 401)
    const hold = holdOf(user)
    ;(user as any).hold = hold.held ? { kind: hold.kind, reason: hold.reason, message: holdMessage(hold) } : null

    return withCors({ user })
  } catch {
    return withCors({ error: 'Failed to fetch profile' }, 500)
  }
}
