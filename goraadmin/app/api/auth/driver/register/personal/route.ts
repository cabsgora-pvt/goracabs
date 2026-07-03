export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Settings from '@/models/Settings'
import Transaction from '@/models/Transaction'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { name, email, state, zoneId, zoneName, profilePicUrl, referralCode } = await req.json()
    if (!name || !state || !zoneId) return withCors({ error: 'Name, state and zone are required' }, 400)

    await connectDB()
    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    driver.name = name
    if (email) driver.email = email
    driver.state = state
    driver.zoneId = zoneId
    driver.zoneName = zoneName
    if (profilePicUrl) driver.profilePicUrl = profilePicUrl
    driver.registrationStep = 'vehicle'

    // ── Apply referral once (Yash referred Manoj → both get admin-set rewards) ──
    let referralApplied = false
    const code = (referralCode || '').toString().trim().toUpperCase()
    if (code && !driver.referredBy && driver.referralCode !== code) {
      const referrer: any = await Driver.findOne({ referralCode: code })
      if (referrer && String(referrer._id) !== String(driver._id)) {
        const s: any = await Settings.findOne({ key: 'global' }).lean()
        const ref = s?.driverApp?.referral || {}
        const refereeReward = Math.round(Number(ref.refereeReward) || 0)
        const referrerReward = Math.round(Number(ref.referrerReward) || 0)

        driver.referredBy = code
        if (refereeReward > 0) {
          driver.walletBalance = (driver.walletBalance || 0) + refereeReward
          driver.referralEarnings = (driver.referralEarnings || 0) + refereeReward
          await Transaction.create({
            driverId: driver._id, type: 'recharge', amount: refereeReward,
            description: `Referral bonus (joined with ${code})`, balanceAfter: driver.walletBalance,
          })
        }
        referrer.referredCount = (referrer.referredCount || 0) + 1
        if (referrerReward > 0) {
          referrer.walletBalance = (referrer.walletBalance || 0) + referrerReward
          referrer.referralEarnings = (referrer.referralEarnings || 0) + referrerReward
          await Transaction.create({
            driverId: referrer._id, type: 'recharge', amount: referrerReward,
            description: `Referral reward (${driver.name || 'a driver'} joined)`, balanceAfter: referrer.walletBalance,
          })
        }
        await referrer.save()
        referralApplied = true
      }
    }

    await driver.save()
    return withCors({ success: true, driver, referralApplied })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
