import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { connectDB } from '@/lib/mongodb'
import Admin from '@/models/Admin'
import { requireAdmin } from '@/lib/auth'

// Settings changes need the admin's own password again (sent in the
// X-Admin-Password header by the panel's password prompt). Returns a response
// to send back when it is missing or wrong, else null.
export async function requireAdminPassword(req: NextRequest): Promise<NextResponse | null> {
  const admin: any = requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const pwd = req.headers.get('x-admin-password') || ''
  if (!pwd) return NextResponse.json({ error: 'Password required to change settings', needsPassword: true }, { status: 428 })
  await connectDB()
  const doc: any = await Admin.findById(admin.id).select('password').lean()
  if (!doc?.password || !(await bcrypt.compare(pwd, doc.password))) {
    return NextResponse.json({ error: 'Wrong password', needsPassword: true, wrongPassword: true }, { status: 403 })
  }
  return null
}
