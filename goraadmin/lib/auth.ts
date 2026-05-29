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
  try { return verifyToken(token) as any } catch { return null }
}
