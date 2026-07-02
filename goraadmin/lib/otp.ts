import bcrypt from 'bcryptjs'
import { connectDB } from '@/lib/mongodb'
import Otp from '@/models/Otp'
import { sendOtpSms, generateOtp } from '@/lib/sms'

const OTP_TTL_MS = 5 * 60 * 1000 // 5 minutes
const RESEND_COOLDOWN_MS = 30 * 1000 // 30 seconds
const MAX_ATTEMPTS = 5

export interface OtpActionResult {
  ok: boolean
  status: number
  error?: string
}

// Generate, store (hashed) and SMS an OTP for a phone+role.
export async function issueOtp(phone: string, role: 'user' | 'driver'): Promise<OtpActionResult> {
  await connectDB()

  const existing: any = await Otp.findOne({ phone, role })
  if (existing?.lastSentAt && Date.now() - new Date(existing.lastSentAt).getTime() < RESEND_COOLDOWN_MS) {
    return { ok: false, status: 429, error: 'Please wait a few seconds before requesting another OTP' }
  }

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
export async function checkOtp(phone: string, otp: string, role: 'user' | 'driver'): Promise<OtpActionResult> {
  await connectDB()

  const rec: any = await Otp.findOne({ phone, role })
  if (!rec) return { ok: false, status: 401, error: 'OTP expired or not requested. Please request a new one.' }

  if (new Date(rec.expiresAt).getTime() < Date.now()) {
    await Otp.deleteOne({ _id: rec._id })
    return { ok: false, status: 401, error: 'OTP expired. Please request a new one.' }
  }

  if (rec.attempts >= MAX_ATTEMPTS) {
    await Otp.deleteOne({ _id: rec._id })
    return { ok: false, status: 429, error: 'Too many wrong attempts. Please request a new OTP.' }
  }

  const match = await bcrypt.compare(String(otp), rec.otpHash)
  if (!match) {
    rec.attempts += 1
    await rec.save()
    return { ok: false, status: 401, error: 'Invalid OTP' }
  }

  await Otp.deleteOne({ _id: rec._id })
  return { ok: true, status: 200 }
}
