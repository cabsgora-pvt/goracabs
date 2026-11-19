export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'
import { ZONE_ADMIN_COOKIE } from '@/lib/zone-admin'

export async function POST() {
  const res = NextResponse.json({ success: true })
  res.cookies.set(ZONE_ADMIN_COOKIE, '', {
    httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 0,
  })
  return res
}
