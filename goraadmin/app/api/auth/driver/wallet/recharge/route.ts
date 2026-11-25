export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth, requireActiveDriver } from '@/lib/auth'
import { creditDriverRecharge } from '@/lib/payment-credit'
import { withCors, corsOptions } from '@/lib/cors'
import { createRazorpayOrder, fetchRazorpayOrder, getRazorpayConfig, verifyRazorpaySignature } from '@/lib/razorpay'
import { DRIVER_RECHARGE } from '@/lib/driver-recharge'

export async function OPTIONS() { return corsOptions() }

// GET  → { enabled, min, max, presets }: can the driver pay online right now.
//
// POST { amount }                          → Razorpay order for that amount.
// POST { orderId, paymentId, signature }   → verify and credit the wallet.
//
// The credit is what Razorpay says was paid on an order WE created for THIS
// driver — never an amount sent by the app — and each payment id is credited
// once, in the same atomic update that adds the money.
export async function GET(req: NextRequest) {
  const payload = requireDriverAuth(req)
  if (!payload) return withCors({ error: 'Unauthorized' }, 401)
  const cfg = await getRazorpayConfig()
  return withCors({ enabled: cfg.enabled, min: DRIVER_RECHARGE.MIN, max: DRIVER_RECHARGE.MAX, presets: DRIVER_RECHARGE.PRESETS })
}

export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveDriver(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const payload = { id: auth.id }
    const b = await req.json().catch(() => ({}))
    await connectDB()

    // ── Step 2: verify + credit ──
    if (b.orderId || b.paymentId || b.signature) {
      const orderId = String(b.orderId || ''), paymentId = String(b.paymentId || ''), signature = String(b.signature || '')
      if (!orderId || !paymentId || !signature) return withCors({ error: 'Missing payment fields' }, 400)
      if (!(await verifyRazorpaySignature(orderId, paymentId, signature))) {
        return withCors({ error: 'Payment verification failed' }, 400)
      }
      const res = await fetchRazorpayOrder(orderId)
      if (!res.ok || !res.order) return withCors({ error: 'Could not confirm the payment with Razorpay. If money was taken, it will be added shortly — contact support.' }, 502)
      const o = res.order
      if (String(o.notes?.purpose || '') !== 'driver_wallet' || String(o.notes?.driverId || '') !== String(payload.id)) {
        return withCors({ error: 'This payment is not a wallet recharge for your account' }, 400)
      }
      const amount = Math.round(Number(o.amount_paid) || 0) / 100
      if (amount <= 0) return withCors({ error: 'Payment not completed yet' }, 400)

      // Same claim as the Razorpay webhook (lib/payment-credit): credited once.
      const out = await creditDriverRecharge(String(payload.id), paymentId, amount)
      return withCors(out.body, out.status)
    }

    // ── Step 1: order ──
    const amount = Number(b.amount)
    if (!Number.isInteger(amount) || amount < DRIVER_RECHARGE.MIN || amount > DRIVER_RECHARGE.MAX) {
      return withCors({ error: `Enter a whole amount between ₹${DRIVER_RECHARGE.MIN} and ₹${DRIVER_RECHARGE.MAX}` }, 400)
    }
    const driver: any = await Driver.findById(payload.id).select('_id').lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    const cfg = await getRazorpayConfig()
    if (!cfg.enabled) {
      return withCors({ error: 'Online recharge is not available yet. Please contact support to add balance.', gatewayOff: true }, 503)
    }
    const receipt = `dw_${payload.id}_${Date.now()}`.slice(0, 40)
    const result = await createRazorpayOrder(amount, receipt, { driverId: String(payload.id), purpose: 'driver_wallet' })
    if (!result.ok) return withCors({ error: result.error || 'Could not start payment' }, 502)
    return withCors({
      orderId: result.order.id,
      keyId: result.keyId,
      amount: result.order.amount,
      currency: result.order.currency,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
