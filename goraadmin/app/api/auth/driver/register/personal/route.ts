export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import mongoose from 'mongoose'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { registrationLocked, LOCKED_CODE } from '@/lib/driver-registration'
import { uploadRef } from '@/lib/ride-view'

// The driver document as the app reads it, without secrets/internal state.
function publicDriver(driver: any) {
  const o: any = driver?.toObject ? driver.toObject() : { ...driver }
  delete o.faceSignature; delete o.walletRechargeRefs; delete o.acceptLeaseUntil
  return o
}

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { name, email, state, zoneId, zoneName, profilePicUrl, referralCode, gender } = await req.json()
    if (!name || !state || !zoneId) return withCors({ error: 'Name, state and zone are required' }, 400)

    await connectDB()
    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // The zone decides which zone admin (franchise) the driver belongs to and
    // which rides they are offered, so it must be a real zone (inactive ones
    // are allowed: drivers sign up before a city opens); its
    // name is taken from the zone itself, not the app.
    const zone: any = mongoose.isValidObjectId(String(zoneId))
      ? await Zone.findById(zoneId).select('name').lean()
      : null
    if (!zone) return withCors({ error: 'Choose a valid service zone' }, 400)

    // Locked once under review / approved (lib/driver-registration.ts): zone,
    // gender and name are checked at approval. Re-sending the same values (an
    // app re-opening the form) is harmless; changing them is refused.
    if (registrationLocked(driver)) {
      const changes: string[] = []
      if (String(driver.zoneId || '') !== String(zone._id)) changes.push('zone')
      if (['female', 'male', 'other'].includes(gender) && gender !== driver.gender) changes.push('gender')
      if (String(name).trim() !== String(driver.name || '').trim()) changes.push('name')
      if (changes.length) {
        return withCors({
          error: changes.includes('zone')
            ? 'Your registration is already submitted. To change your zone, send a zone-change request from Settings → Zone.'
            : `Your registration is already submitted. Contact support to change your ${changes.join(' / ')}.`,
          code: LOCKED_CODE, locked: changes,
        }, 409)
      }
      if (email) driver.email = email
      await driver.save()
      return withCors({ success: true, driver: publicDriver(driver), referralApplied: false })
    }

    driver.name = name
    if (email) driver.email = email
    driver.state = state
    driver.zoneId = String(zone._id)
    driver.zoneName = zone.name || zoneName
    // Never over the face scan, which is the driver's photo once taken.
    if (profilePicUrl && !driver.faceReferencePhotoUrl) {
      const pic = uploadRef(profilePicUrl, req)
      if (pic) driver.profilePicUrl = pic
    }
    if (['female', 'male', 'other'].includes(gender)) driver.gender = gender
    driver.registrationStep = 'vehicle'

    // ── Referral: only RECORDED here. The rewards are paid once, when an admin
    // approves this driver (drivers/{id}/approve) — paying at step 1 let anyone
    // farm them with throwaway sign-ups that were never approved.
    let referralApplied = false
    const code = (referralCode || '').toString().trim().toUpperCase()
    if (code && !driver.referredBy && driver.referralCode !== code) {
      const referrer: any = await Driver.findOne({ referralCode: code }).select('_id').lean()
      if (referrer && String(referrer._id) !== String(driver._id)) {
        driver.referredBy = code
        referralApplied = true
      }
    }

    await driver.save()
    return withCors({ success: true, driver: publicDriver(driver), referralApplied, referralRewardOnApproval: referralApplied })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
