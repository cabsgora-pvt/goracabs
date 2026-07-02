import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'

export interface SmsResult {
  success: boolean
  message: string
  raw?: string
}

// Reads the live SMS config from the DB Settings doc (admin-managed, NOT env).
async function getSmsConfig(): Promise<any> {
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).lean()
  return s?.sms || {}
}

// Convert a raw phone into "91XXXXXXXXXX" (country code required by SMS Indori).
function normalizeNumber(phone: string): string {
  let p = String(phone).replace(/\D/g, '')
  if (p.length === 10) p = '91' + p
  return p
}

// Low-level: send an arbitrary (already DLT-compliant) message to one number.
export async function sendSms(phone: string, message: string): Promise<SmsResult> {
  const sms = await getSmsConfig()
  const provider = (sms.provider || 'smsindori').toLowerCase()
  const number = normalizeNumber(phone)

  try {
    // ---- SMS Indori (token-key HTTP API) ----
    if (provider === 'smsindori') {
      const c = sms.smsindori || {}
      const apiUrl = c.apiUrl || 'http://sms.smsindori.com/http-tokenkeyapi.php'
      if (!c.authKey || !c.senderId || !c.templateId) {
        return { success: false, message: 'SMS Indori not configured (auth key / sender id / template id missing)' }
      }
      const routeVal = encodeURIComponent(c.route || '16')
      const url =
        `${apiUrl}?authentic-key=${encodeURIComponent(c.authKey)}` +
        `&senderid=${encodeURIComponent(c.senderId)}` +
        `&route=${routeVal}&routeid=${routeVal}` +
        `&number=${encodeURIComponent(number)}` +
        `&message=${encodeURIComponent(message)}` +
        `&templateid=${encodeURIComponent(c.templateId)}`
      const res = await fetch(url, { method: 'GET' })
      const text = await res.text()
      const ok = res.ok && !/error|invalid|fail|insufficient|not\s*found/i.test(text)
      // Log for VPS debugging (key masked)
      console.log(`[SMS Indori] number=${number} sender=${c.senderId} tpl=${c.templateId} route=${c.route || '16'} httpStatus=${res.status} response=${text}`)
      return { success: ok, message: ok ? 'SMS sent' : `SMS Indori error: ${text}`, raw: text }
    }

    // ---- MSG91 (legacy HTTP API) ----
    if (provider === 'msg91') {
      const c = sms.msg91 || {}
      if (!c.authKey || !c.senderId) return { success: false, message: 'MSG91 not configured' }
      const url =
        `https://api.msg91.com/api/sendhttp.php?authkey=${encodeURIComponent(c.authKey)}` +
        `&mobiles=${encodeURIComponent(number)}&message=${encodeURIComponent(message)}` +
        `&sender=${encodeURIComponent(c.senderId)}&route=4&country=91` +
        (c.templateId ? `&DLT_TE_ID=${encodeURIComponent(c.templateId)}` : '')
      const res = await fetch(url)
      const text = await res.text()
      const ok = res.ok && !/error/i.test(text)
      return { success: ok, message: ok ? 'SMS sent' : `MSG91 error: ${text}`, raw: text }
    }

    // ---- Twilio (REST, HTTP basic auth — no SDK needed) ----
    if (provider === 'twilio') {
      const c = sms.twilio || {}
      if (!c.accountSid || !c.authToken || !c.fromNumber) return { success: false, message: 'Twilio not configured' }
      const to = number.startsWith('91') ? `+${number}` : `+91${number}`
      const body = new URLSearchParams({ From: c.fromNumber, To: to, Body: message })
      const auth = Buffer.from(`${c.accountSid}:${c.authToken}`).toString('base64')
      const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${c.accountSid}/Messages.json`, {
        method: 'POST',
        headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded' },
        body,
      })
      const text = await res.text()
      return { success: res.ok, message: res.ok ? 'SMS sent' : `Twilio error: ${text}`, raw: text }
    }

    return { success: false, message: `Unknown SMS provider: ${provider}` }
  } catch (e: any) {
    return { success: false, message: e?.message || 'SMS send failed' }
  }
}

// Build the DLT-approved OTP message (substituting the OTP into the template)
// and send it. Template placeholder can be {#numeric#}, {#var#} or ##OTP##.
export async function sendOtpSms(phone: string, otp: string): Promise<SmsResult> {
  const sms = await getSmsConfig()
  const provider = (sms.provider || 'smsindori').toLowerCase()
  const providerCfg = sms[provider] || {}
  const template =
    providerCfg.templateText ||
    'Your Gora Cabs OTP is {#numeric#}. It is valid for 5 minutes. Do not share it with anyone.'
  const message = template.replace(/\{#numeric#\}|\{#var#\}|##otp##/gi, otp)
  return sendSms(phone, message)
}

// 6-digit numeric OTP.
export function generateOtp(): string {
  return String(Math.floor(100000 + Math.random() * 900000))
}
