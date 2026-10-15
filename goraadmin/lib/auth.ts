import jwt from 'jsonwebtoken'
import { NextRequest } from 'next/server'

const JWT_SECRET = process.env.JWT_SECRET!

export function signToken(payload: object) {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' })
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

export function requireDriverAuth(req: NextRequest) {
  const token = getDriverTokenFromRequest(req)
  if (!token) return null
  try {
    const p = verifyToken(token) as any
    // A rider token is signed with the same secret; never let it pass as a driver.
    return p?.type === 'user' ? null : p
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
