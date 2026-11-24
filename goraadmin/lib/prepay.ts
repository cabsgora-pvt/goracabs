// ─────────────────────────────────────────────────────────────────────────────
// Upfront payments, tied to the ride they paid for.
//
// Outstation is the one service the rider app charges BEFORE booking (wallet
// debit via /wallet/pay, or a Razorpay checkout verified via
// /payment/razorpay/verify). Neither left any link to the ride: the wallet
// debit is written with ref '' (the ride does not exist yet) and the Razorpay
// payment id was never stored anywhere. So nothing could ever give that money
// back if the ride did not happen.
//
// linkPrepayment runs right after the ride is created and records what was
// actually captured, from a server-verified source only:
//   wallet → the rider's own, still-unlinked ride debit from the last few
//            minutes (claimed atomically, so one debit can back only one ride)
//   online → a Razorpay order whose signature verifies, that Razorpay itself
//            reports as paid, and whose notes name this rider and purpose
//            'ride' (we stamped those notes when creating the order)
// A client-sent amount is never trusted.
//
// When a ride was charged upfront but the payment cannot be tied to it (an app
// build that does not send the Razorpay ids, a gateway lookup failure), the
// ride is flagged prepaidUnlinked and is never auto-closed for "No driver
// found" — closing it would strand the rider's money with no way back.
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import { verifyRazorpaySignature, fetchRazorpayOrder } from './razorpay'

/** How far back a wallet debit may be and still count as this booking's. */
export const PREPAY_WALLET_WINDOW_MS = 10 * 60 * 1000

/** Services the rider app charges before a driver is found. */
export function chargedAtBooking(service: string, paymentMode: string): boolean {
  return service === 'outstation' && (paymentMode === 'wallet' || paymentMode === 'online')
}

type Linked = { amount: number; via: 'wallet' | 'online'; ref: string }

async function linkWallet(ride: any, riderId: string): Promise<Linked | null> {
  const since = new Date(new Date(ride.createdAt || Date.now()).getTime() - PREPAY_WALLET_WINDOW_MS)
  // Claim: flips ref '' → this ride atomically, so two bookings racing cannot
  // both point at the same debit.
  const row: any = await WalletTransaction.findOneAndUpdate(
    { userId: riderId, type: 'debit', source: 'ride', ref: '', createdAt: { $gte: since } },
    { $set: { ref: String(ride._id) } },
    { sort: { createdAt: -1 }, new: true },
  ).lean()
  if (!row) return null
  const amount = Number(row.amount) || 0
  // A debit larger than the whole fare is not this booking's payment. Put the
  // claim back rather than tie an unrelated charge to the ride.
  if (amount <= 0 || amount > (Number(ride.totalFare ?? ride.fare) || 0) + 1) {
    await WalletTransaction.updateOne({ _id: row._id, ref: String(ride._id) }, { $set: { ref: '' } })
    return null
  }
  return { amount, via: 'wallet', ref: String(row._id) }
}

async function linkOnline(ride: any, riderId: string, prepaid: any): Promise<Linked | null> {
  const orderId = String(prepaid?.orderId || '')
  const paymentId = String(prepaid?.paymentId || '')
  const signature = String(prepaid?.signature || '')
  if (!orderId || !paymentId || !signature) return null
  if (!(await verifyRazorpaySignature(orderId, paymentId, signature))) return null

  const res = await fetchRazorpayOrder(orderId)
  if (!res.ok || !res.order) return null
  const o = res.order
  if (String(o.notes?.userId || '') !== String(riderId)) return null
  if (String(o.notes?.purpose || '') !== 'ride') return null
  const amount = Math.round((Number(o.amount_paid) || 0)) / 100
  if (amount <= 0) return null
  if (amount > (Number(ride.totalFare ?? ride.fare) || 0) + 1) return null

  // One payment backs one ride.
  const used = await Ride.exists({ prepaidRef: paymentId, _id: { $ne: ride._id } })
  if (used) return null
  // Claim the payment on the rider, atomically. A refused booking refunds the
  // same payment by claiming this same token (refundRefusedPrepayment), so a
  // payment is either tied to a ride or given back, never both.
  const claimed = await User.updateOne(
    { _id: riderId, walletRechargeRefs: { $ne: prepayToken(paymentId) } },
    { $push: { walletRechargeRefs: prepayToken(paymentId) } },
  )
  if (!claimed.modifiedCount) return null
  return { amount, via: 'online', ref: paymentId }
}

/** The claim a Razorpay prepayment leaves on the rider (see linkOnline). */
export function prepayToken(paymentId: string): string {
  return `prepay:${paymentId}`
}

export type RefusedRefund = { amount: number; via: 'wallet' | 'online'; balance: number }

/**
 * Gives back an outstation prepayment whose booking was refused (account on
 * hold, quote expired, any error) before a ride was created. Without this the
 * rider's money backed no ride and nothing could ever return it.
 *
 * Same trust rules as linking: only money the server itself can verify —
 *   wallet → the rider's own unlinked ride debit from the last few minutes
 *   online → a verified, paid Razorpay order with this rider's notes, purpose
 *            'ride', not already tied to a ride
 * It is refunded to the rider's Gora wallet, the convention every refund here
 * follows (lib/refunds.ts). Each payment can be claimed once, atomically:
 * a retried or doubled request refunds nothing more. Never throws.
 */
export async function refundRefusedPrepayment(riderId: string, body: any): Promise<RefusedRefund | null> {
  try {
    const mode = body?.paymentMode === 'cod' ? 'cash' : String(body?.paymentMode || 'cash')
    if (!chargedAtBooking(String(body?.service || 'taxi'), mode)) return null
    const fare = Number(body?.fare)
    const bound = Number.isFinite(fare) && fare > 0 ? fare + 1 : null

    if (mode === 'wallet') {
      const since = new Date(Date.now() - PREPAY_WALLET_WINDOW_MS)
      const debit: any = await WalletTransaction.findOneAndUpdate(
        {
          userId: riderId, type: 'debit', source: 'ride', ref: '', createdAt: { $gte: since },
          ...(bound ? { amount: { $lte: bound } } : {}),
        },
        { $set: { ref: 'refused-booking' } },
        { sort: { createdAt: -1 }, new: true },
      ).lean()
      if (!debit) return null
      const amount = Math.round((Number(debit.amount) || 0) * 100) / 100
      if (amount <= 0) return null
      return await credit(riderId, amount, `refund:refused:${debit._id}`, `refund:refused:${debit._id}`, 'wallet')
    }

    const orderId = String(body?.prepaid?.orderId || '')
    const paymentId = String(body?.prepaid?.paymentId || '')
    const signature = String(body?.prepaid?.signature || '')
    if (!orderId || !paymentId || !signature) return null
    if (!(await verifyRazorpaySignature(orderId, paymentId, signature))) return null
    const res = await fetchRazorpayOrder(orderId)
    if (!res.ok || !res.order) return null
    const o = res.order
    if (String(o.notes?.userId || '') !== String(riderId)) return null
    if (String(o.notes?.purpose || '') !== 'ride') return null
    const amount = Math.round(Number(o.amount_paid) || 0) / 100
    if (amount <= 0) return null
    if (await Ride.exists({ prepaidRef: paymentId })) return null
    return await credit(riderId, amount, prepayToken(paymentId), `refund:refused:${paymentId}`, 'online')
  } catch (e) {
    console.error('[prepay] refused-booking refund failed', e)
    return null
  }
}

// Claim `token` and add `amount` in one atomic update on the rider.
async function credit(riderId: string, amount: number, token: string, txRef: string, via: 'wallet' | 'online'): Promise<RefusedRefund | null> {
  const user: any = await User.findOneAndUpdate(
    { _id: riderId, walletRechargeRefs: { $ne: token } },
    { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: token } },
    { new: true },
  ).select('walletBalance').lean()
  if (!user) return null
  await WalletTransaction.create({
    userId: riderId, type: 'credit', amount, balanceAfter: user.walletBalance || 0,
    note: 'Refund: your outstation trip could not be booked', source: 'refund', ref: txRef,
  })
  return { amount, via, balance: user.walletBalance || 0 }
}

/**
 * Records the upfront payment on a freshly created ride. Never throws and never
 * blocks the booking.
 *
 * Fail-safe by construction: /rides/book creates such a ride with
 * prepaidUnlinked already true, and only a successful link clears it. Any
 * failure here — including this update itself — leaves the ride out of the
 * automatic "No driver found" close rather than closing it without a refund.
 */
export async function linkPrepayment(ride: any, riderId: string | undefined, body: any): Promise<void> {
  if (!chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))) return
  try {
    if (!riderId) return
    const linked = ride.paymentMode === 'wallet'
      ? await linkWallet(ride, String(riderId))
      : await linkOnline(ride, String(riderId), body?.prepaid)
    if (!linked) return
    await Ride.updateOne(
      { _id: ride._id },
      { $set: { prepaidAmount: linked.amount, prepaidVia: linked.via, prepaidRef: linked.ref, prepaidUnlinked: false } },
    )
  } catch (e) {
    console.error('[prepay] link failed', e)
  }
}
