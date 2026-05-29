import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { signToken } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

const DEFAULT_OTP = '1234'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const { phone, otp } = await req.json()

    if (otp !== DEFAULT_OTP) {
      return withCors({ error: 'Invalid OTP. Use 1234' }, 401)
    }

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
