import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import crypto from 'crypto'
import { connectDB } from '@/lib/mongodb'
import Admin from '@/models/Admin'
import { requireActiveAdmin, getTokenFromRequest } from '@/lib/auth'
import { limitHit, limitPeek } from '@/lib/rate-limit'

// ─────────────────────────────────────────────────────────────────────────────
// Re-authentication for settings, money, pricing and destructive admin routes.
//
// The panel's password prompt sends the admin's own password in the
// X-Admin-Password header. A correct password opens a SUDO_MS "sudo" window
// bound to that session token (sha256 stored on the Admin doc), so the next
// clicks in the same session within 5 minutes don't prompt again. Another
// session — e.g. a stolen token — gets no window. Wrong passwords are limited
// to 10 per 15 minutes per admin.
//
// Returns a response to send back (401 / 428 needsPassword / 403 wrongPassword
// / 429) when refused, else null.
// ─────────────────────────────────────────────────────────────────────────────

export const SUDO_MS = 5 * 60_000

const tokenHash = (t: string) => crypto.createHash('sha256').update(t).digest('hex')

export async function requireAdminPassword(req: NextRequest): Promise<NextResponse | null> {
  const admin: any = await requireActiveAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const token = getTokenFromRequest(req) || ''
  const th = tokenHash(token)
  const pwd = req.headers.get('x-admin-password') || ''
  await connectDB()
  const doc: any = await Admin.findById(admin.id).select('password sudoUntil sudoTokenHash').lean()
  if (!doc?.password) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  if (!pwd) {
    const inSudo = doc.sudoUntil && new Date(doc.sudoUntil).getTime() > Date.now() && doc.sudoTokenHash === th
    if (inSudo) return null
    return NextResponse.json({ error: 'Enter your password to confirm this change', needsPassword: true }, { status: 428 })
  }

  const failKey = `admin-pwd-fail:${admin.id}`
  if ((await limitPeek(failKey, 15 * 60_000)) >= 10) {
    return NextResponse.json({ error: 'Too many wrong passwords. Try again in 15 minutes.', needsPassword: true }, { status: 429 })
  }
  if (!(await bcrypt.compare(pwd, doc.password))) {
    await limitHit(failKey, 10, 15 * 60_000)
    return NextResponse.json({ error: 'Wrong password', needsPassword: true, wrongPassword: true }, { status: 403 })
  }
  await Admin.updateOne({ _id: doc._id }, { $set: { sudoUntil: new Date(Date.now() + SUDO_MS), sudoTokenHash: th } })
  return null
}
