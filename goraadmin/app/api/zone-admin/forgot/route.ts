export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import { logZoneActivity } from '@/lib/zone-admin'
import { rateLimit } from '@/lib/rate-limit'
import { isFranchiseMode } from '@/lib/franchise'

// POST { email } — "Forgot password". There is no email/SMS channel for
// arbitrary messages yet (SMS needs a DLT template per message), so the request
// is flagged for whoever can reset it: the super admin for a zone admin, the
// zone admin for their staff. The answer is the same whether or not the email
// exists, so it cannot be used to find accounts.
export async function POST(req: NextRequest) {
  try {
    if (!rateLimit(req, 'zone-admin-forgot', 5, 60_000)) {
      return NextResponse.json({ error: 'Too many requests. Wait a minute.' }, { status: 429 })
    }
    const { email } = await req.json()
    const e = String(email || '').toLowerCase().trim()
    if (e && await isFranchiseMode()) {
      await connectDB()
      const admin: any = await ZoneAdmin.findOne({ email: e })
      if (admin) {
        admin.passwordResetRequestedAt = new Date(); await admin.save()
        await logZoneActivity(admin._id, { type: 'zone_admin', id: String(admin._id), name: admin.name }, 'password.reset_requested')
      } else {
        const staff: any = await ZoneStaff.findOne({ email: e })
        if (staff) {
          staff.passwordResetRequestedAt = new Date(); await staff.save()
          await logZoneActivity(staff.zoneAdminId, { type: 'staff', id: String(staff._id), name: staff.name }, 'password.reset_requested')
        }
      }
    }
    return NextResponse.json({ success: true, message: 'If this email is registered, Gora (or your zone admin) has been asked to reset your password. They will share a new one with you.' })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
