export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { ZONE_ADMIN_COOKIE, logZoneActivity, signZoneAdminToken } from '@/lib/zone-admin'

// POST — "Login as zone admin": opens their panel in this browser for support.
// The session is marked as the super admin's, logged, and lasts two hours; it
// cannot change the zone admin's password. Expiry and blocking still apply.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const a: any = await ZoneAdmin.findById(params.id).select('name').lean()
  if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const by = requireAdmin(req)?.email || 'super admin'
  await logZoneActivity(a._id, { type: 'super_admin', id: '', name: by }, 'admin.view_as')
  const res = NextResponse.json({ success: true, url: '/zone-panel' })
  res.cookies.set(ZONE_ADMIN_COOKIE, signZoneAdminToken(String(a._id), { impersonatedBy: by }), {
    httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 2 * 3600,
  })
  return res
}
