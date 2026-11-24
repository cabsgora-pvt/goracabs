export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { signToken } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkOtp } from '@/lib/otp'
import { normalizePhone } from '@/lib/phone'
import { rateLimit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    if (!rateLimit(req, 'user-verify-otp', 30, 10 * 60_000)) {
      return withCors({ error: 'Too many attempts. Try again in a few minutes.' }, 429)
    }
    const body = await req.json().catch(() => null)
    const phone = normalizePhone(body?.phone)
    const otp = body?.otp
    if (!phone || !otp) return withCors({ error: 'Valid 10-digit mobile number and OTP are required' }, 400)
    if (!/^\d{4,8}$/.test(String(otp))) return withCors({ error: 'Invalid OTP' }, 401)

    const verify = await checkOtp(phone, String(otp), 'user')
    if (!verify.ok) return withCors({ error: verify.error }, verify.status)

    await connectDB()

    let user = await User.findOne({ phone })
    let isNewUser = false

    if (!user) {
      user = await User.create({ phone, status: 'active' })
      isNewUser = true
    }

    const token = signToken({ id: user._id, phone: user.phone, type: 'user' })

    return withCors({
      token,
      isNewUser,
      user: {
        id: user._id,
        name: user.name,
        phone: user.phone,
        email: user.email,
        status: user.status,
        walletBalance: user.walletBalance,
      },
    })
  } catch {
    return withCors({ error: 'Verification failed' }, 500)
  }
}
