export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { requireActiveAdmin, bumpTokenVersion } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'

// Logout revokes, not just forgets: bumping the admin's tokenVersion makes
// every token issued to them so far invalid (this browser, any other browser,
// and a copied token). `?scope=` is accepted for clarity but every logout is a
// "log out everywhere" — admin tokens carry one shared version.
export async function POST(req: NextRequest) {
  const admin: any = await requireActiveAdmin(req).catch(() => null)
  if (admin?.id) {
    await bumpTokenVersion('admin', String(admin.id)).catch(() => {})
    await auditAdmin(req, admin, 'admin.logout', { summary: 'All sessions revoked' })
  }
  const res = NextResponse.json({ success: true, revoked: !!admin?.id })
  res.cookies.set('admin_token', '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: 0,
  })
  return res
}
