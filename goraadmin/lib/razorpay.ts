import crypto from 'crypto'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'

export interface RazorpayActiveConfig {
  enabled: boolean
  mode: 'test' | 'live'
  keyId: string
  keySecret: string
}

// Reads Razorpay config from the DB Settings doc and returns the ACTIVE
// key pair based on the selected mode (test/live). Secret never leaves server.
export async function getRazorpayConfig(): Promise<RazorpayActiveConfig> {
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).lean()
  const rp = s?.payment?.razorpay || {}
  const mode: 'test' | 'live' = rp.mode === 'live' ? 'live' : 'test'
  const keyId = mode === 'live' ? rp.liveKeyId : rp.testKeyId
  const keySecret = mode === 'live' ? rp.liveKeySecret : rp.testKeySecret
  return {
    enabled: !!rp.enabled && !!keyId && !!keySecret,
    mode,
    keyId: keyId || '',
    keySecret: keySecret || '',
  }
}

// Create a Razorpay order via REST API (no SDK needed). amount is in rupees.
export async function createRazorpayOrder(
  amountRupees: number,
  receipt: string,
  notes: Record<string, string> = {}
): Promise<{ ok: boolean; order?: any; keyId?: string; error?: string }> {
  const cfg = await getRazorpayConfig()
  if (!cfg.enabled) return { ok: false, error: 'Razorpay is not enabled' }

  const auth = Buffer.from(`${cfg.keyId}:${cfg.keySecret}`).toString('base64')
  try {
    const res = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        amount: Math.round(amountRupees * 100), // paise
        currency: 'INR',
        receipt,
        notes,
      }),
    })
    const data = await res.json()
    if (!res.ok) {
      console.log(`[Razorpay] order failed mode=${cfg.mode} keyId=${cfg.keyId ? cfg.keyId.slice(0, 12) + '…' : 'EMPTY'} status=${res.status} resp=${JSON.stringify(data)}`)
      return { ok: false, error: data?.error?.description || 'Failed to create order' }
    }
    console.log(`[Razorpay] order OK mode=${cfg.mode} keyId=${cfg.keyId.slice(0, 12)}… orderId=${data.id}`)
    return { ok: true, order: data, keyId: cfg.keyId }
  } catch (e: any) {
    console.log(`[Razorpay] order exception: ${e?.message}`)
    return { ok: false, error: e?.message || 'Razorpay request failed' }
  }
}

// Verify the payment signature returned by Razorpay checkout.
export async function verifyRazorpaySignature(
  orderId: string,
  paymentId: string,
  signature: string
): Promise<boolean> {
  const cfg = await getRazorpayConfig()
  if (!cfg.keySecret) return false
  const expected = crypto
    .createHmac('sha256', cfg.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest('hex')
  // constant-time compare
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(signature))
  } catch {
    return false
  }
}
