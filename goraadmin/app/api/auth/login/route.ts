export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Admin from '@/models/Admin'
import bcrypt from 'bcryptjs'
import { signAdminToken, ADMIN_TOKEN_TTL_SECONDS } from '@/lib/auth'
import { rateLimitAsync, limitHit, limitPeek, limitReset } from '@/lib/rate-limit'
import { auditAdmin } from '@/lib/admin-audit'

// Per-email lockout: after MAX_FAILS wrong passwords inside the 15-minute
// window the address is locked for the rest of it, whatever the caller IP.
// Counted in Mongo (lib/rate-limit), so a restart does not reset it.
const MAX_FAILS = 5
const FAIL_WINDOW = 15 * 60_000

export async function POST(req: NextRequest) {
  try {
    // Password guessing: 10 tries a minute per IP.
    if (!(await rateLimitAsync(req, 'admin-login', 10, 60_000))) {
      return NextResponse.json({ error: 'Too many attempts. Wait a minute and try again.' }, { status: 429 })
    }
    let body: any
    try { body = await req.json() } catch { return NextResponse.json({ error: 'Invalid request' }, { status: 400 }) }
    const { email, password } = body || {}
    if (!email || !password || typeof email !== 'string' || typeof password !== 'string') {
      return NextResponse.json({ error: 'Email and password required' }, { status: 400 })
    }
    const e = email.toLowerCase().trim()
    const failKey = `admin-login-fail:${e}`
    if ((await limitPeek(failKey, FAIL_WINDOW)) >= MAX_FAILS) {
      return NextResponse.json({ error: 'Too many failed attempts for this account. Try again in 15 minutes.' }, { status: 429 })
    }
    await connectDB()
    const admin = await Admin.findOne({ email: e })
    const valid = admin ? await bcrypt.compare(password, admin.password) : false
    if (!admin || !valid) {
      await limitHit(failKey, MAX_FAILS, FAIL_WINDOW)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }
    await limitReset(failKey, FAIL_WINDOW)

    // Typed 'admin' + tv (tokenVersion): logout bumps the version, which
    // revokes this token everywhere. The token travels only in the HttpOnly
    // cookie — never in the JSON body, where page script could read it.
    const token = signAdminToken(admin)
    const res = NextResponse.json({
      success: true,
      admin: { id: admin._id, name: admin.name, email: admin.email, role: admin.role },
    })
    res.cookies.set('admin_token', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'strict',
      path: '/',
      maxAge: ADMIN_TOKEN_TTL_SECONDS,
    })
    await auditAdmin(req, { id: String(admin._id), email: admin.email }, 'admin.login')
    return res
  } catch (error: any) {
    return NextResponse.json({ error: 'Server error' }, { status: 500 })
  }
}
