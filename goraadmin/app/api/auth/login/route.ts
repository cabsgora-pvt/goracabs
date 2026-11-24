export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Admin from '@/models/Admin'
import bcrypt from 'bcryptjs'
import { signToken, ADMIN_TOKEN_TTL, ADMIN_TOKEN_TTL_SECONDS } from '@/lib/auth'
import { rateLimit } from '@/lib/rate-limit'

// Per-email lockout (in-process, single VPS): after MAX_FAILS wrong passwords
// inside FAIL_WINDOW the address is locked for LOCK_MS, whatever the caller IP.
const MAX_FAILS = 5
const FAIL_WINDOW = 15 * 60_000
const LOCK_MS = 15 * 60_000
const fails = new Map<string, { times: number[]; lockedUntil: number }>()

function lockState(email: string) {
  const now = Date.now()
  const s = fails.get(email)
  if (!s) return { locked: false, s: { times: [] as number[], lockedUntil: 0 } }
  s.times = s.times.filter(t => t > now - FAIL_WINDOW)
  return { locked: s.lockedUntil > now, s }
}

function recordFail(email: string) {
  const { s } = lockState(email)
  s.times.push(Date.now())
  if (s.times.length >= MAX_FAILS) { s.lockedUntil = Date.now() + LOCK_MS; s.times = [] }
  fails.set(email, s)
  if (fails.size > 5000) {
    const now = Date.now()
    for (const [k, v] of fails) if (v.lockedUntil < now && !v.times.some(t => t > now - FAIL_WINDOW)) fails.delete(k)
  }
}

export async function POST(req: NextRequest) {
  try {
    // Password guessing: 10 tries a minute per IP.
    if (!rateLimit(req, 'admin-login', 10, 60_000)) {
      return NextResponse.json({ error: 'Too many attempts. Wait a minute and try again.' }, { status: 429 })
    }
    let body: any
    try { body = await req.json() } catch { return NextResponse.json({ error: 'Invalid request' }, { status: 400 }) }
    const { email, password } = body || {}
    if (!email || !password || typeof email !== 'string' || typeof password !== 'string') {
      return NextResponse.json({ error: 'Email and password required' }, { status: 400 })
    }
    const e = email.toLowerCase().trim()
    if (lockState(e).locked) {
      return NextResponse.json({ error: 'Too many failed attempts for this account. Try again in 15 minutes.' }, { status: 429 })
    }
    await connectDB()
    const admin = await Admin.findOne({ email: e })
    const valid = admin ? await bcrypt.compare(password, admin.password) : false
    if (!admin || !valid) {
      recordFail(e)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }
    fails.delete(e)

    const token = signToken({ id: admin._id, email: admin.email, role: admin.role }, ADMIN_TOKEN_TTL)
    const res = NextResponse.json({
      success: true,
      token,
      admin: { id: admin._id, name: admin.name, email: admin.email, role: admin.role },
    })
    res.cookies.set('admin_token', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax',
      path: '/',
      maxAge: ADMIN_TOKEN_TTL_SECONDS,
    })
    return res
  } catch (error: any) {
    return NextResponse.json({ error: 'Server error' }, { status: 500 })
  }
}
