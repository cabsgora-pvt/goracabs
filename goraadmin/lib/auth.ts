import jwt from 'jsonwebtoken'
import { NextRequest } from 'next/server'

const JWT_SECRET = process.env.JWT_SECRET!

/** Rider/driver tokens live 7 days (the apps re-login on 401). Admin tokens are
 *  shorter-lived — pass ADMIN_TOKEN_TTL from the admin login route. */
export const ADMIN_TOKEN_TTL = '12h'
export const ADMIN_TOKEN_TTL_SECONDS = 12 * 60 * 60

export function signToken(payload: object, expiresIn: string | number = '7d') {
  return jwt.sign(payload, JWT_SECRET, { expiresIn } as jwt.SignOptions)
}

export function verifyToken(token: string) {
  return jwt.verify(token, JWT_SECRET)
}

export function getTokenFromRequest(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (auth?.startsWith('Bearer ')) return auth.slice(7)
  return req.cookies.get('admin_token')?.value || null
}

export function getDriverTokenFromRequest(req: NextRequest) {
  const auth = req.headers.get('authorization')
  if (auth?.startsWith('Bearer ')) return auth.slice(7)
  return req.cookies.get('driver_token')?.value || null
}

export function requireAuth(req: NextRequest) {
  const token = getTokenFromRequest(req)
  if (!token) return null
  try { return verifyToken(token) } catch { return null }
}

/** Driver-app callers only: the payload must be typed 'driver'. Rider, admin and
 *  zone-admin tokens share the secret and are rejected here — admin tooling must
 *  use requireAdmin / guardAdmin instead. */
export function requireDriverAuth(req: NextRequest) {
  const token = getDriverTokenFromRequest(req)
  if (!token) return null
  try {
    const p = verifyToken(token) as any
    return p?.type === 'driver' && p?.id ? p : null
  } catch { return null }
}

/** Rider-app callers only: the payload must be typed 'user'. */
export function requireRider(req: NextRequest) {
  const auth = req.headers.get('authorization')
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return null
  try {
    const p = verifyToken(token) as any
    return p?.type === 'user' && p?.id ? p : null
  } catch { return null }
}

// Admin tokens (auth/login) carry a role and no `type`; rider and driver tokens
// are typed 'user' / 'driver'. All three share one secret, so a valid signature
// alone does not make the caller an admin.
export function isAdminPayload(p: any): boolean {
  return !!p?.id && !p.type
}

export function requireAdmin(req: NextRequest) {
  const p = requireAuth(req) as any
  return isAdminPayload(p) ? p : null
}
