export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Settings from '@/models/Settings'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

function genCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  let s = ''
  for (let i = 0; i < 5; i++) s += chars[Math.floor(Math.random() * chars.length)]
  return 'GORA' + s
}

// GET /api/auth/driver/referral → { code, referrerReward, refereeReward, referredCount, referralEarnings }
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Lazily generate a unique referral code
    if (!driver.referralCode) {
      let code = genCode()
      for (let i = 0; i < 6; i++) {
        const exists = await Driver.findOne({ referralCode: code }).lean()
        if (!exists) break
        code = genCode()
      }
      driver.referralCode = code
      await driver.save()
    }

    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const ref = s?.driverApp?.referral || {}

    return withCors({
      code: driver.referralCode,
      referrerReward: ref.referrerReward ?? 0,
      refereeReward: ref.refereeReward ?? 0,
      referredCount: driver.referredCount || 0,
      referralEarnings: driver.referralEarnings || 0,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
