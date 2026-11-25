import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Settings from '@/models/Settings'
import Transaction from '@/models/Transaction'
import mongoose from 'mongoose'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'
import { approvalBlocker, approveDriverAtomic } from '@/lib/driver-approval'

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    // Only a submitted, complete, pending/rejected registration (lib/driver-approval).
    const current: any = await Driver.findById(params.id).select('status registrationStep documents selectedVehicleTypeName vehicleType name').lean()
    const chk = await approvalBlocker(current)
    if (!chk.ok) return NextResponse.json({ error: chk.error, code: chk.code, missing: chk.missing }, { status: chk.status })
    const driver: any = await approveDriverAtomic(params.id, { rejectionReason: '' })
    if (!driver) return NextResponse.json({ error: 'Driver changed while approving — reload and try again', code: 'CONFLICT' }, { status: 409 })
    await auditAdmin(req, requireAdmin(req), 'driver.approve', { target: `driver:${params.id}`, summary: `Approved ${current.name || 'driver'} (was ${current.status})` })

    const referral = await payReferralOnApproval(driver).catch(e => {
      console.error('[approve] referral payout failed', e)
      return null
    })
    return NextResponse.json({ success: true, driver, referral })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

/**
 * Referral rewards (admin-set amounts in Settings → driverApp.referral), paid
 * ONCE per referred driver, at approval. The claim on `referralRewardPaid` is
 * one atomic update, so approving twice, or two admins approving at the same
 * moment, pays exactly once. Recorded at registration step 1 (referredBy) but
 * no longer paid there, where unapproved throwaway sign-ups could farm it.
 */
async function payReferralOnApproval(driver: any) {
  const code = String(driver.referredBy || '').trim().toUpperCase()
  if (!code || driver.referralRewardPaid) return null
  const referrer: any = await Driver.findOne({ referralCode: code, _id: { $ne: driver._id } }).select('_id name').lean()
  if (!referrer) return null

  const claimed: any = await Driver.findOneAndUpdate(
    { _id: driver._id, status: 'approved', referralRewardPaid: { $ne: true } },
    { $set: { referralRewardPaid: true } },
    { new: true },
  ).select('_id').lean()
  if (!claimed) return null

  const s: any = await Settings.findOne({ key: 'global' }).lean()
  const ref = s?.driverApp?.referral || {}
  const refereeReward = Math.max(0, Math.round(Number(ref.refereeReward) || 0))
  const referrerReward = Math.max(0, Math.round(Number(ref.referrerReward) || 0))

  if (refereeReward > 0) {
    const d: any = await Driver.findByIdAndUpdate(driver._id,
      { $inc: { walletBalance: refereeReward, referralEarnings: refereeReward } }, { new: true }).select('walletBalance').lean()
    await Transaction.create({
      driverId: driver._id, type: 'recharge', amount: refereeReward,
      description: `Referral bonus (joined with ${code})`, balanceAfter: d?.walletBalance,
    })
  }
  const r: any = await Driver.findByIdAndUpdate(referrer._id,
    { $inc: { referredCount: 1, ...(referrerReward > 0 ? { walletBalance: referrerReward, referralEarnings: referrerReward } : {}) } },
    { new: true }).select('walletBalance').lean()
  if (referrerReward > 0) {
    await Transaction.create({
      driverId: referrer._id, type: 'recharge', amount: referrerReward,
      description: `Referral reward (${driver.name || 'a driver'} joined)`, balanceAfter: r?.walletBalance,
    })
  }
  return { code, refereeReward, referrerReward, referrerId: String(referrer._id) }
}
