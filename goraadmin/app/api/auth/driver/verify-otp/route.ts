export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { signToken } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkOtp } from '@/lib/otp'
import { normalizePhone } from '@/lib/phone'
import { rateLimit } from '@/lib/rate-limit'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    if (!rateLimit(req, 'driver-verify-otp', 30, 10 * 60_000)) {
      return withCors({ error: 'Too many attempts. Try again in a few minutes.' }, 429)
    }
    const body = await req.json().catch(() => null)
    const phone = normalizePhone(body?.phone)
    const otp = body?.otp
    if (!phone || !otp) return withCors({ error: 'Valid 10-digit mobile number and OTP are required' }, 400)
    if (!/^\d{4,8}$/.test(String(otp))) return withCors({ error: 'Invalid OTP' }, 401)

    const verify = await checkOtp(phone, String(otp), 'driver')
    if (!verify.ok) return withCors({ error: verify.error }, verify.status)

    await connectDB()

    // Find or create driver
    let driver = await Driver.findOne({ phone }).lean() as any
    if (!driver) {
      const created = await Driver.create({ phone, registrationStep: 'otp', status: 'pending' })
      driver = created.toObject()
    }

    const token = signToken({ id: driver._id, phone, type: 'driver' })

    // Set cookie
    const response = withCors(
      driver.status === 'approved'
        ? { token, driver, isApproved: true }
        : driver.status === 'rejected'
        ? { token, driver, isRejected: true, rejectionReason: driver.rejectionReason }
        : driver.registrationStep === 'submitted'
        ? { token, driver, registrationStep: 'submitted' }
        : { token, driver, registrationStep: driver.registrationStep || 'otp' }
    )

    response.cookies.set('driver_token', token, {
      httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 7 * 24 * 3600,
    })
    return response
  } catch (error: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
