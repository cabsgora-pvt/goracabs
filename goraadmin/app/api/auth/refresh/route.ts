export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'
import {
  requireRider, requireDriverAuth, requireActiveRider, requireActiveDriver,
  signToken, refreshAfterOf, REFRESH_MIN_AGE_SECONDS, APP_TOKEN_TTL_SECONDS,
} from '@/lib/auth'
import { limitHit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/refresh   Authorization: Bearer <rider or driver token>
// Sliding sessions: a token at least a day old, on an account that is still
// active (not blocked / deleted / revoked), is exchanged for a new 7-day token
// carrying the current tokenVersion. The apps call it when a profile response's
// `refreshAfter` has passed, so nobody is logged out weekly any more.
//   200 { token, expiresIn, refreshAfter, type }
//   409 { code: 'TOO_EARLY', refreshAfter }   token younger than a day
//   401 / 403 { code }                        see lib/auth activeDenied
export async function POST(req: NextRequest) {
  try {
    const kind = requireDriverAuth(req) ? 'driver' : requireRider(req) ? 'user' : null
    if (!kind) return withCors({ error: 'Unauthorized', code: 'UNAUTHORIZED' }, 401)
    const a = kind === 'driver' ? await requireActiveDriver(req) : await requireActiveRider(req)
    if (!a.ok) return withCors({ error: a.error, code: a.code }, a.status)

    const iat = Number(a.payload.iat || 0)
    if (!iat || Date.now() / 1000 - iat < REFRESH_MIN_AGE_SECONDS) {
      return withCors({ error: 'Token is still fresh', code: 'TOO_EARLY', refreshAfter: refreshAfterOf(a.payload) }, 409)
    }
    if (!(await limitHit(`refresh:${kind}:${a.id}`, 20, 86_400_000))) {
      return withCors({ error: 'Too many refreshes today', code: 'RATE_LIMIT' }, 429)
    }
    await connectDB()
    const Model: any = kind === 'driver' ? Driver : User
    const doc: any = await Model.findById(a.id).select('phone').lean()
    if (!doc) return withCors({ error: 'Unauthorized', code: 'UNAUTHORIZED' }, 401)

    const token = signToken({ id: String(a.id), phone: doc.phone, type: kind, tv: a.tv }, APP_TOKEN_TTL_SECONDS)
    const now = Math.floor(Date.now() / 1000)
    const res = withCors({ token, type: kind, expiresIn: APP_TOKEN_TTL_SECONDS, refreshAfter: refreshAfterOf({ iat: now }) })
    if (kind === 'driver' && req.cookies.get('driver_token')?.value) {
      res.cookies.set('driver_token', token, { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: APP_TOKEN_TTL_SECONDS })
    }
    return res
  } catch {
    return withCors({ error: 'Refresh failed' }, 500)
  }
}
