import { holdOf, holdMessage } from '@/lib/account-hold'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { requireRider, refreshAfterOf } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    // Rider tokens only (it used to accept any signed token, admin included).
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const user = await User.findById(payload.id).lean()
    if (!user) return withCors({ error: 'User not found' }, 404)
    // A deleted account is signed out on its next call.
    if ((user as any).status === 'deleted') return withCors({ error: 'Unauthorized', accountDeleted: true, code: 'ACCOUNT_DELETED' }, 401)
    // A revoked session (blocked / logged out everywhere) signs in again.
    const tv = Number((user as any).tokenVersion || 0)
    if ((payload.tv ?? 0) !== tv) return withCors({ error: 'Your session has ended. Please sign in again.', code: 'SESSION_REVOKED' }, 401)
    delete (user as any).walletRechargeRefs
    delete (user as any).tokenVersion
    const hold = holdOf(user)
    ;(user as any).hold = hold.held ? { kind: hold.kind, reason: hold.reason, message: holdMessage(hold) } : null

    // refreshAfter: when the app should call POST /api/auth/refresh.
    return withCors({ user, refreshAfter: refreshAfterOf(payload) })
  } catch {
    return withCors({ error: 'Failed to fetch profile' }, 500)
  }
}
