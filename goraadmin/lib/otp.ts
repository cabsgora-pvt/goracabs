import bcrypt from 'bcryptjs'
import { connectDB } from '@/lib/mongodb'
import Otp from '@/models/Otp'
import OtpSendLog from '@/models/OtpSendLog'
import { sendOtpSms, generateOtp } from '@/lib/sms'

const OTP_TTL_MS = 5 * 60 * 1000 // 5 minutes
const RESEND_COOLDOWN_MS = 30 * 1000 // 30 seconds
const MAX_ATTEMPTS = 5
// Daily send caps (rolling 24h), counted in OtpSendLog. Callers also apply an
// in-memory per-IP burst limit (lib/rate-limit) before calling issueOtp.
export const MAX_SENDS_PER_PHONE_PER_DAY = 10
export const MAX_SENDS_PER_IP_PER_DAY = 30

export interface OtpActionResult {
  ok: boolean
  status: number
  error?: string
}

// Generate, store (hashed) and SMS an OTP for a phone+role.
// `phone` must already be normalised (lib/phone normalizePhone).
export async function issueOtp(phone: string, role: 'user' | 'driver', ip = ''): Promise<OtpActionResult> {
  await connectDB()

  const dayAgo = new Date(Date.now() - 24 * 3600 * 1000)
  const [byPhone, byIp] = await Promise.all([
    OtpSendLog.countDocuments({ phone, createdAt: { $gt: dayAgo } }),
    ip ? OtpSendLog.countDocuments({ ip, createdAt: { $gt: dayAgo } }) : Promise.resolve(0),
  ])
  if (byPhone >= MAX_SENDS_PER_PHONE_PER_DAY) {
    return { ok: false, status: 429, error: 'Too many OTP requests for this number today. Try again tomorrow.' }
  }
  if (ip && byIp >= MAX_SENDS_PER_IP_PER_DAY) {
    return { ok: false, status: 429, error: 'Too many OTP requests. Try again later.' }
  }

  const existing: any = await Otp.findOne({ phone, role })
  if (existing?.lastSentAt && Date.now() - new Date(existing.lastSentAt).getTime() < RESEND_COOLDOWN_MS) {
    return { ok: false, status: 429, error: 'Please wait a few seconds before requesting another OTP' }
  }

  await OtpSendLog.create({ phone, role, ip })

  const otp = generateOtp()
  const otpHash = await bcrypt.hash(otp, 10)
  const expiresAt = new Date(Date.now() + OTP_TTL_MS)

  await Otp.findOneAndUpdate(
    { phone, role },
    { phone, role, otpHash, attempts: 0, lastSentAt: new Date(), expiresAt },
    { upsert: true, new: true }
  )

  const sms = await sendOtpSms(phone, otp)
  if (!sms.success) {
    return { ok: false, status: 502, error: sms.message || 'Failed to send OTP' }
  }
  return { ok: true, status: 200 }
}

// Verify an entered OTP for a phone+role. On success the record is deleted.
// The attempt is counted atomically BEFORE the bcrypt compare, so N parallel
// guesses can never get more than MAX_ATTEMPTS compares between them.
export async function checkOtp(phone: string, otp: string, role: 'user' | 'driver'): Promise<OtpActionResult> {
  await connectDB()

  const now = new Date()
  const rec: any = await Otp.findOneAndUpdate(
    { phone, role, expiresAt: { $gt: now }, attempts: { $lt: MAX_ATTEMPTS } },
    { $inc: { attempts: 1 } },
    { new: true },
  ).lean()

  if (!rec) {
    const any: any = await Otp.findOne({ phone, role }).lean()
    if (!any) return { ok: false, status: 401, error: 'OTP expired or not requested. Please request a new one.' }
    await Otp.deleteOne({ _id: any._id })
    if (new Date(any.expiresAt).getTime() <= now.getTime()) {
      return { ok: false, status: 401, error: 'OTP expired. Please request a new one.' }
    }
    return { ok: false, status: 429, error: 'Too many wrong attempts. Please request a new OTP.' }
  }

  const match = await bcrypt.compare(String(otp), rec.otpHash)
  if (!match) return { ok: false, status: 401, error: 'Invalid OTP' }

  // Single use: only the caller that actually deletes the record wins.
  const del = await Otp.deleteOne({ _id: rec._id, otpHash: rec.otpHash })
  if (!del.deletedCount) return { ok: false, status: 401, error: 'OTP already used. Please request a new one.' }
  return { ok: true, status: 200 }
}
