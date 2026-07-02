export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { signToken } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkOtp } from '@/lib/otp'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const { phone, otp } = await req.json()
    if (!phone || !otp) return withCors({ error: 'Phone and OTP are required' }, 400)

    const verify = await checkOtp(String(phone), String(otp), 'driver')
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

    response.cookies.set('driver_token', token, { httpOnly: true, maxAge: 7 * 24 * 3600 })
    return response
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
