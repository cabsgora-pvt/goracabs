export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireActiveRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature, fetchRazorpayOrder } from '@/lib/razorpay'
import { creditRiderTopUp, payRideWithPayment } from '@/lib/payment-credit'

export async function OPTIONS() { return corsOptions() }

// POST /api/payment/razorpay/verify
// body: { orderId, paymentId, signature, purpose, rideId? }
//   'wallet'            → credits the wallet with what Razorpay captured (idempotent)
//   'ride' + rideId     → pays that online ride (see payRide below)
//   'ride' w/o rideId, 'outstation_prepay' → signature check only; /rides/book
//                         ties the payment to the booking (lib/prepay.ts)
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveRider(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const payload = { id: auth.id }

    // No 'amount' here: what to credit comes from Razorpay, never from the app.
    const body = await req.json().catch(() => ({}))
    const { orderId, paymentId, signature } = body
    const purpose = String(body.purpose || 'wallet')
    const rideId = body.rideId ? String(body.rideId) : ''
    if (!orderId || !paymentId || !signature) return withCors({ error: 'Missing payment fields' }, 400)

    const valid = await verifyRazorpaySignature(String(orderId), String(paymentId), String(signature))
    if (!valid) return withCors({ error: 'Payment verification failed' }, 400)

    await connectDB()

    if (purpose === 'wallet') {
      // Credit what Razorpay says was paid on an order created for THIS user.
      const res = await fetchRazorpayOrder(String(orderId))
      if (!res.ok || !res.order) return withCors({ error: 'Could not confirm the payment with Razorpay' }, 502)
      const o = res.order
      if (String(o.notes?.userId || '') !== String(payload.id) || String(o.notes?.purpose || 'wallet') !== 'wallet') {
        return withCors({ error: 'This payment is not a wallet top-up for your account' }, 400)
      }
      const amt = Math.round(Number(o.amount_paid) || 0) / 100
      if (amt <= 0) return withCors({ error: 'Payment not completed yet' }, 400)

      // Same claim as the Razorpay webhook (lib/payment-credit): credited once.
      const out = await creditRiderTopUp(String(payload.id), String(paymentId), amt)
      return withCors(out.body, out.status)
    }

    if (purpose === 'ride' && rideId) return await payRide(String(payload.id), rideId, String(orderId), String(paymentId))

    // Prepayment before booking: verified only; book links it to the ride.
    return withCors({ success: true, paymentId, rideId })
  } catch {
    return withCors({ error: 'Verification failed' }, 500)
  }
}

// Paying an online ride with a verified Razorpay payment.
//   - The order must be OURS for this rider and this ride (notes we stamped).
//   - Then lib/payment-credit payRideWithPayment: the payment id is claimed once
//     on the rider ("ridepay:<id>", the same claim the webhook takes), attached
//     to the ride while it is an unpaid online ride and settled; a payment that
//     cannot pay the ride is credited to the rider's wallet.
// -> { success, paymentStatus, amountPaid, amountDue, pendingCompletion?,
//      refundedToWallet?, alreadyProcessed?, code? }
async function payRide(userId: string, rideId: string, orderId: string, paymentId: string) {
  if (!mongoose.isValidObjectId(rideId)) return withCors({ error: 'Ride not found' }, 404)
  const res = await fetchRazorpayOrder(orderId)
  if (!res.ok || !res.order) return withCors({ error: 'Could not confirm the payment with Razorpay' }, 502)
  const o = res.order
  if (String(o.notes?.userId || '') !== userId || String(o.notes?.purpose || '') !== 'ride' || String(o.notes?.rideId || '') !== rideId) {
    return withCors({ error: 'This payment is not for this ride', code: 'wrongOrder' }, 400)
  }
  const amount = Math.round(Number(o.amount_paid) || 0) / 100
  if (amount <= 0) return withCors({ error: 'Payment not completed yet' }, 400)

  // Claim + attach + settle: lib/payment-credit (shared with the webhook).
  const out = await payRideWithPayment(userId, rideId, orderId, paymentId, amount)
  return withCors(out.body, out.status)
}
