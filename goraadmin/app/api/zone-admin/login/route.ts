export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import { rateLimit } from '@/lib/rate-limit'
import { FRANCHISE_OFF_MESSAGE, isFranchiseMode } from '@/lib/franchise'
import { ACCESS_MESSAGE, ZONE_ADMIN_COOKIE, accessState, logZoneActivity, signZoneAdminToken } from '@/lib/zone-admin'

// One sign-in for zone admins and their staff.
export async function POST(req: NextRequest) {
  try {
    // Password guessing: 10 tries a minute per address.
    if (!rateLimit(req, 'zone-admin-login', 10, 60_000)) {
      return NextResponse.json({ error: 'Too many attempts. Wait a minute and try again.' }, { status: 429 })
    }
    if (!(await isFranchiseMode())) return NextResponse.json({ error: FRANCHISE_OFF_MESSAGE, access: 'franchise_off' }, { status: 403 })
    await connectDB()
    const { email, password } = await req.json()
    if (!email || !password) return NextResponse.json({ error: 'Email and password required' }, { status: 400 })
    const e = String(email).toLowerCase().trim()

    let admin: any = await ZoneAdmin.findOne({ email: e })
    let staff: any = null
    if (admin) {
      if (!(await bcrypt.compare(String(password), admin.password))) admin = null
    } else {
      staff = await ZoneStaff.findOne({ email: e })
      if (staff && (await bcrypt.compare(String(password), staff.password))) {
        if (staff.status !== 'active') return NextResponse.json({ error: 'Your staff login is blocked. Contact your zone admin.' }, { status: 403 })
        admin = await ZoneAdmin.findById(staff.zoneAdminId)
      } else {
        staff = null
      }
    }
    if (!admin) return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })

    // Blocked or expired: say why at the door. The grace period still opens,
    // read-only, so they can see what to renew.
    const state = accessState(admin)
    if (state !== 'active' && state !== 'grace') return NextResponse.json({ error: ACCESS_MESSAGE[state], access: state }, { status: 403 })

    const who = staff || admin
    who.lastLoginAt = new Date()
    await who.save()
    await logZoneActivity(admin._id, staff ? { type: 'staff', id: String(staff._id), name: staff.name } : { type: 'zone_admin', id: String(admin._id), name: admin.name }, 'login')

    const token = signZoneAdminToken(String(admin._id), staff ? { staffId: String(staff._id) } : {})
    const res = NextResponse.json({ success: true, zoneAdmin: { id: admin._id, name: who.name, email: who.email, staff: !!staff } })
    res.cookies.set(ZONE_ADMIN_COOKIE, token, {
      httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 7 * 24 * 3600,
    })
    return res
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
