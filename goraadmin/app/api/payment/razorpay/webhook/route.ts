export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import crypto from 'crypto'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { fetchRazorpayOrder } from '@/lib/razorpay'
import { creditRiderTopUp, payRideWithPayment, creditDriverRecharge, applySubscriptionFromOrder } from '@/lib/payment-credit'
import { isPrepayOrder, notePrepayCaptured } from '@/lib/prepay'

// POST /api/payment/razorpay/webhook — Razorpay → Gora, server to server.
//
// Configure in the Razorpay Dashboard → Settings → Webhooks → Add:
//   URL     https://<admin host>/api/payment/razorpay/webhook
//           (production: https://admin.<your domain>/api/payment/razorpay/webhook)
//   Secret  any long random string; paste the same value in the admin panel →
//           Settings → Payment → Razorpay → Webhook Secret
//           (settings.payment.razorpay.webhookSecret; RAZORPAY_WEBHOOK_SECRET env
//           is used when the setting is empty)
//   Events  payment.captured, order.paid
//
// Why: a rider/driver whose app dies right after paying never calls /verify,
// so the money was taken and nothing was credited. The webhook applies the
// same payment through the SAME code and claim keys as the app's own
// confirmation (lib/payment-credit), so app + webhook in any order credit once.
//
// Security: X-Razorpay-Signature = HMAC-SHA256(raw body, webhook secret),
// compared in constant time; anything else → 401. What to credit is read from
// Razorpay's own copy of the order (the notes we stamped when creating it).
//
// Purposes (order notes.purpose):
//   wallet              → rider wallet top-up (claim <paymentId>)
//   ride (+ rideId)     → pay that online ride (claim ridepay:<paymentId>)
//   outstation_prepay   → left for /rides/book to link; recorded so the orphan
//     (or legacy ride     sweep refunds it to the wallet if no ride links it
//      without rideId)    within 30 minutes
//   driver_wallet       → driver wallet recharge (claim <paymentId>)
//   driver_subscription → activate the pass (claim sub:<paymentId>)
// Always answers 200 once the signature checks out (unknown events/purposes are
// logged and acknowledged); 500 only for a transient failure Razorpay should retry.
const HANDLED = new Set(['payment.captured', 'order.paid'])

async function webhookSecret(): Promise<string> {
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).select('payment').lean()
  return String(s?.payment?.razorpay?.webhookSecret || process.env.RAZORPAY_WEBHOOK_SECRET || '')
}

function signatureOk(raw: string, signature: string, secret: string): boolean {
  if (!secret || !signature) return false
  const expected = crypto.createHmac('sha256', secret).update(raw).digest('hex')
  const a = Buffer.from(expected), b = Buffer.from(String(signature))
  return a.length === b.length && crypto.timingSafeEqual(a, b)
}

export async function POST(req: NextRequest) {
  const raw = await req.text()
  let secret = ''
  try { secret = await webhookSecret() } catch { return NextResponse.json({ error: 'Unavailable' }, { status: 500 }) }
  if (!secret) {
    console.warn('[rzp-webhook] no webhook secret configured; event refused')
    return NextResponse.json({ error: 'Webhook not configured' }, { status: 401 })
  }
  if (!signatureOk(raw, req.headers.get('x-razorpay-signature') || '', secret)) {
    return NextResponse.json({ error: 'Invalid signature' }, { status: 401 })
  }

  let evt: any
  try { evt = JSON.parse(raw) } catch { return NextResponse.json({ ok: true, ignored: 'bad json' }) }
  const event = String(evt?.event || '')
  if (!HANDLED.has(event)) {
    console.log('[rzp-webhook] ignored event', event)
    return NextResponse.json({ ok: true, ignored: event })
  }

  const payment = evt?.payload?.payment?.entity || {}
  const orderEnt = evt?.payload?.order?.entity || {}
  const paymentId = String(payment.id || '')
  const orderId = String(payment.order_id || orderEnt.id || '')
  if (!paymentId || !orderId) {
    console.warn('[rzp-webhook] event without payment/order id', event)
    return NextResponse.json({ ok: true, ignored: 'no ids' })
  }
  if (payment.status && payment.status !== 'captured') {
    return NextResponse.json({ ok: true, ignored: `payment ${payment.status}` })
  }

  try {
    // Razorpay's own copy of the order: the notes we stamped and amount_paid.
    let o: any = null
    const res = await fetchRazorpayOrder(orderId)
    if (res.ok && res.order) o = res.order
    else if (orderEnt?.id === orderId && orderEnt?.notes) o = orderEnt
    if (!o) {
      console.error('[rzp-webhook] could not read order', orderId, res.error)
      return NextResponse.json({ error: 'Order lookup failed' }, { status: 500 })
    }
    let paise = Number(o.amount_paid) || 0
    if (!(paise > 0) && payment.status === 'captured' && String(payment.order_id || '') === orderId) paise = Number(payment.amount) || 0
    const amount = Math.round(paise) / 100
    const notes = o.notes || {}
    const purpose = String(notes.purpose || '')
    const userId = String(notes.userId || '')
    const driverId = String(notes.driverId || '')
    let result: any = null

    if (purpose === 'wallet' && mongoose.isValidObjectId(userId)) {
      result = await creditRiderTopUp(userId, paymentId, amount)
    } else if (purpose === 'ride' && notes.rideId && mongoose.isValidObjectId(userId)) {
      result = await payRideWithPayment(userId, String(notes.rideId), orderId, paymentId, amount)
    } else if (isPrepayOrder({ ...o, notes }) && mongoose.isValidObjectId(userId)) {
      await notePrepayCaptured({ paymentId, orderId, userId, amount })
      result = { status: 200, body: { recorded: 'prepay' } }
    } else if (purpose === 'driver_wallet' && mongoose.isValidObjectId(driverId)) {
      result = await creditDriverRecharge(driverId, paymentId, amount)
    } else if (['driver_subscription', 'subscription'].includes(purpose)) {
      result = await applySubscriptionFromOrder(o, paymentId)
    } else {
      console.warn('[rzp-webhook] unknown purpose', { event, orderId, paymentId, purpose })
      return NextResponse.json({ ok: true, ignored: 'unknown purpose' })
    }
    console.log('[rzp-webhook]', event, purpose, paymentId, result?.status, JSON.stringify(result?.body || {}).slice(0, 200))
    return NextResponse.json({ ok: true, purpose, status: result?.status })
  } catch (e: any) {
    console.error('[rzp-webhook] failed', e?.message || e)
    return NextResponse.json({ error: 'Processing failed' }, { status: 500 })
  }
}
