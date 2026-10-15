export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

function genCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let s = ''
  for (let i = 0; i < 5; i++) s += chars[Math.floor(Math.random() * chars.length)]
  return 'GORA' + s
}

// GET /api/auth/user/referral → { code, referredCount, referralEarnings }
export async function GET(req: NextRequest) {
  try {
    const payload: any = requireAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const user: any = await User.findById(payload.id)
    if (!user) return withCors({ error: 'User not found' }, 404)

    // Lazily generate a unique referral code, same as the driver app.
    if (!user.referralCode) {
      let code = genCode()
      for (let i = 0; i < 6; i++) {
        const exists = await User.findOne({ referralCode: code }).lean()
        if (!exists) break
        code = genCode()
      }
      user.referralCode = code
      await user.save()
    }

    return withCors({
      code: user.referralCode,
      referredCount: user.referredCount || 0,
      referralEarnings: user.referralEarnings || 0,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
