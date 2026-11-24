export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { verifyRazorpaySignature, fetchRazorpayOrder } from '@/lib/razorpay'
import { settleOnlinePayment, refundRidePayment } from '@/lib/settlement'
import User from '@/models/User'
import Ride from '@/models/Ride'
import WalletTransaction from '@/models/WalletTransaction'

export async function OPTIONS() { return corsOptions() }

// POST /api/payment/razorpay/verify
// body: { orderId, paymentId, signature, purpose, rideId? }
//   'wallet'            → credits the wallet with what Razorpay captured (idempotent)
//   'ride' + rideId     → pays that online ride (see payRide below)
//   'ride' w/o rideId, 'outstation_prepay' → signature check only; /rides/book
//                         ties the payment to the booking (lib/prepay.ts)
export async function POST(req: NextRequest) {
  try {
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

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

      if (await WalletTransaction.exists({ ref: paymentId, source: 'recharge' })) {
        const u: any = await User.findById(payload.id).select('walletBalance').lean()
        return withCors({ success: true, alreadyCredited: true, balance: u?.walletBalance || 0 })
      }
      const updated: any = await User.findOneAndUpdate(
        { _id: payload.id, walletRechargeRefs: { $ne: paymentId } },
        { $inc: { walletBalance: amt }, $push: { walletRechargeRefs: paymentId } },
        { new: true },
      ).select('walletBalance').lean()
      if (!updated) {
        const u: any = await User.findById(payload.id).select('walletBalance').lean()
        if (!u) return withCors({ error: 'User not found' }, 404)
        return withCors({ success: true, alreadyCredited: true, balance: u.walletBalance || 0 })
      }
      await WalletTransaction.create({
        userId: updated._id, type: 'credit', amount: amt, balanceAfter: updated.walletBalance,
        note: 'Money added via Razorpay', source: 'recharge', ref: paymentId,
      })
      return withCors({ success: true, amount: amt, balance: updated?.walletBalance || 0 })
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
//   - The payment id is claimed once on the rider (walletRechargeRefs
//     "ridepay:<id>"), so a replay or a doubled request does nothing more.
//   - It is attached to the ride only while the ride is an unpaid online ride;
//     a completed ride is then settled at once (driver credited exactly once by
//     lib/settlement settleOnlinePayment), an ongoing one when it completes.
//   - A payment that cannot pay the ride (less than amountDue, ride already
//     paid / switched to cash / cancelled) is credited to the rider's wallet.
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

  const ride: any = await Ride.findById(rideId).select('riderId').lean()
  if (!ride) return withCors({ error: 'Ride not found' }, 404)
  if (String(ride.riderId || '') !== userId) return withCors({ error: 'Not your ride' }, 403)

  const token = `ridepay:${paymentId}`
  const claimed = await User.updateOne({ _id: userId, walletRechargeRefs: { $ne: token } }, { $push: { walletRechargeRefs: token } })
  if (!claimed.modifiedCount) {
    const r: any = await Ride.findById(rideId).select('paymentStatus amountDue').lean()
    return withCors({ success: r?.paymentStatus === 'paid', alreadyProcessed: true, paymentStatus: r?.paymentStatus, amountDue: r?.amountDue })
  }

  const attached: any = await Ride.findOneAndUpdate(
    {
      _id: rideId, riderId: userId, paymentMode: 'online', paymentStatus: 'pending',
      status: { $in: ['accepted', 'arrived', 'ongoing', 'completed'] },
      'onlinePayment.paymentId': { $exists: false },
    },
    { $set: { onlinePayment: { paymentId, orderId, amount, at: new Date(), settled: false } } },
    { new: true },
  ).lean()
  if (!attached) {
    const refunded = await refundRidePayment(userId, paymentId, amount, 'Refund: this ride was not awaiting an online payment')
    const r: any = await Ride.findById(rideId).select('paymentStatus paymentMode amountDue').lean()
    return withCors({
      success: false, error: `This ride is not awaiting an online payment. ₹${refunded} was added to your Gora wallet.`,
      code: 'notAwaitingPayment', refundedToWallet: refunded, paymentStatus: r?.paymentStatus, paymentMode: r?.paymentMode,
    }, 409)
  }

  const s = await settleOnlinePayment(rideId)
  if (s.state === 'paid' || s.state === 'already') {
    return withCors({ success: true, paymentStatus: 'paid', amountPaid: amount, amountDue: s.amountDue ?? attached.amountDue })
  }
  if (s.state === 'held') {
    return withCors({ success: true, paymentStatus: 'pending', pendingCompletion: true, amountPaid: amount, amountDue: attached.amountDue })
  }
  if (s.state === 'short') {
    return withCors({
      success: false, code: 'amountShort',
      error: `₹${amount} paid but ₹${s.amountDue} is due. The ₹${s.refunded || 0} was added to your Gora wallet; please pay again.`,
      paymentStatus: 'pending', amountPaid: amount, amountDue: s.amountDue, refundedToWallet: s.refunded || 0,
    }, 402)
  }
  return withCors({
    success: false, code: 'notAwaitingPayment',
    error: `This ride is no longer awaiting payment. ₹${s.refunded || 0} was added to your Gora wallet.`,
    refundedToWallet: s.refunded || 0,
  }, 409)
}
