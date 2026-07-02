export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { signToken } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkOtp } from '@/lib/otp'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const { phone, otp } = await req.json()
    if (!phone || !otp) return withCors({ error: 'Phone and OTP are required' }, 400)

    const verify = await checkOtp(String(phone), String(otp), 'user')
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
