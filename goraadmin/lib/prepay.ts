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
//            reports as paid, and whose notes name this rider and are a PREPAY
//            order (isPrepayOrder: purpose 'outstation_prepay', or legacy
//            'ride' with no rideId created in the last 30 minutes)
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
import RazorpayPrepay from '@/models/RazorpayPrepay'
import { verifyRazorpaySignature, fetchRazorpayOrder } from './razorpay'

/** How far back a wallet debit may be and still count as this booking's. */
export const PREPAY_WALLET_WINDOW_MS = 10 * 60 * 1000

/** Services the rider app charges before a driver is found. */
export function chargedAtBooking(service: string, paymentMode: string): boolean {
  return service === 'outstation' && (paymentMode === 'wallet' || paymentMode === 'online')
}

export type Linked = { amount: number; via: 'wallet' | 'online'; ref: string }

/** A legacy prepay order (purpose 'ride', no rideId) only counts this fresh. */
export const LEGACY_PREPAY_ORDER_MS = 30 * 60 * 1000

/**
 * Whether a Razorpay order is an outstation PREPAYMENT (as opposed to a
 * post-ride payment, a wallet top-up, ...). New app builds create these with
 * notes.purpose 'outstation_prepay'. Older builds used purpose 'ride' with no
 * rideId; those count only when the order was created in the last 30 minutes.
 * A purpose 'ride' order that names a rideId is a payment FOR that ride and is
 * never a prepayment — so it can neither back a booking nor be "refunded" by a
 * refused booking.
 */
export function isPrepayOrder(o: any, now = Date.now()): boolean {
  const purpose = String(o?.notes?.purpose || '')
  if (purpose === 'outstation_prepay') return true
  if (purpose !== 'ride') return false
  if (String(o?.notes?.rideId || '')) return false
  const created = Number(o?.created_at) * 1000
  return Number.isFinite(created) && created > 0 && now - created <= LEGACY_PREPAY_ORDER_MS
}

// The largest prepayment that may back this ride: the booking passes a cap
// (excess is refunded there); legacy linking keeps the fare + ₹1 rule.
const boundOf = (ride: any) => ride.maxPrepay != null ? Number(ride.maxPrepay) : (Number(ride.totalFare ?? ride.fare) || 0) + 1

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
  if (amount <= 0 || amount > boundOf(ride)) {
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
  if (!isPrepayOrder(o)) return null
  const amount = Math.round((Number(o.amount_paid) || 0)) / 100
  if (amount <= 0) return null
  if (amount > boundOf(ride)) return null

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
 *   online → a verified, paid Razorpay PREPAY order (isPrepayOrder) with this rider's notes,
 *            not already tied to a ride
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
    if (!isPrepayOrder(o)) return null
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
async function credit(riderId: string, amount: number, token: string, txRef: string, via: 'wallet' | 'online', note = 'Refund: your outstation trip could not be booked'): Promise<RefusedRefund | null> {
  const user: any = await User.findOneAndUpdate(
    { _id: riderId, walletRechargeRefs: { $ne: token } },
    { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: token } },
    { new: true },
  ).select('walletBalance').lean()
  if (!user) return null
  await WalletTransaction.create({
    userId: riderId, type: 'credit', amount, balanceAfter: user.walletBalance || 0,
    note, source: 'refund', ref: txRef,
  })
  return { amount, via, balance: user.walletBalance || 0 }
}

/**
 * Claims the upfront payment for a ride that is ABOUT to be created (its _id
 * chosen by the caller), from a server-verified source only. Used by
 * /rides/book, which refuses (402) to create a prepaid ride whose verified
 * payment does not cover the fare. Never throws.
 */
export async function claimPrepayment(
  ride: { _id: any; service: string; paymentMode: string; totalFare: number; fare: number; createdAt?: Date; maxPrepay?: number },
  riderId: string | undefined,
  body: any,
): Promise<Linked | null> {
  if (!chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))) return null
  if (!riderId) return null
  try {
    return ride.paymentMode === 'wallet'
      ? await linkWallet(ride, String(riderId))
      : await linkOnline(ride, String(riderId), body?.prepaid)
  } catch (e) {
    console.error('[prepay] claim failed', e)
    return null
  }
}

/**
 * Gives back a prepayment claimed by claimPrepayment for a booking that was
 * then refused (it did not cover the fare). Once per payment. Never throws.
 */
export async function refundClaimedPrepayment(riderId: string, linked: Linked): Promise<RefusedRefund | null> {
  try {
    const amount = Math.round((Number(linked.amount) || 0) * 100) / 100
    if (amount <= 0) return null
    if (linked.via === 'wallet') {
      // The debit was claimed for the never-created ride; mark it refused.
      await WalletTransaction.updateOne({ _id: linked.ref }, { $set: { ref: 'refused-booking' } })
      return await credit(riderId, amount, `refund:refused:${linked.ref}`, `refund:refused:${linked.ref}`, 'wallet')
    }
    return await credit(riderId, amount, `refund:short:${linked.ref}`, `refund:refused:${linked.ref}`, 'online')
  } catch (e) {
    console.error('[prepay] refund of claimed prepayment failed', e)
    return null
  }
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

/**
 * The part of a linked prepayment above what the booking needed, back to the
 * rider's wallet — once per payment (claim `prepay-excess:<ref>`). The ref
 * deliberately carries the payment, not the ride, so finance never mistakes it
 * for a refund of a completed ride's revenue. Never throws.
 */
export async function refundPrepayExcess(riderId: string, linked: Linked, excess: number): Promise<RefusedRefund | null> {
  try {
    const amount = Math.round((Number(excess) || 0) * 100) / 100
    if (amount <= 0) return null
    return await credit(riderId, amount, `prepay-excess:${linked.ref}`, `refund:prepay-excess:${linked.ref}`, linked.via,
      'Refund: you paid more than this outstation trip costs')
  } catch (e) {
    console.error('[prepay] excess refund failed', e)
    return null
  }
}

/** A wallet prepayment (ref '') this old is never linked (linking looks back 10 min). */
export const ORPHAN_WALLET_MS = 15 * 60 * 1000
/** A webhook-seen Razorpay prepayment no booking linked within this is refunded. */
export const ORPHAN_ONLINE_MS = 30 * 60 * 1000
/** Older orphans are left for an admin: they predate the booking-time claim and
 *  may belong to a legacy ride that went ahead unlinked. */
export const ORPHAN_HORIZON_MS = 3 * 24 * 60 * 60 * 1000

// A ride that was charged upfront but could not be tied to its payment
// (prepaidUnlinked) near the time of this payment may be the one it paid for:
// refunding it automatically could hand back the fare of a trip that happens.
async function unlinkedRideNear(userId: any, at: Date): Promise<boolean> {
  const t = new Date(at).getTime()
  return !!(await Ride.exists({
    riderId: userId, prepaidUnlinked: true,
    createdAt: { $gte: new Date(t - 5 * 60_000), $lte: new Date(t + ORPHAN_ONLINE_MS) },
  }))
}

/**
 * Records an outstation prepayment Razorpay reported as captured (webhook), so
 * the orphan sweep can refund it if no booking ever links it. Idempotent.
 */
export async function notePrepayCaptured(p: { paymentId: string; orderId: string; userId: string; amount: number }): Promise<void> {
  if (!p.paymentId || !p.userId || !(p.amount > 0)) return
  await RazorpayPrepay.updateOne(
    { paymentId: p.paymentId },
    { $setOnInsert: { paymentId: p.paymentId, orderId: p.orderId, userId: p.userId, amount: p.amount, state: 'open' } },
    { upsert: true },
  ).catch((e: any) => { if (e?.code !== 11000) throw e })
}

/** Orphan refs an admin may still refund by hand (see refundOrphanWalletDebit). */
export const ADMIN_ORPHAN_REFS = ['', 'orphan-review', 'orphan-refund']

export type OrphanAdminRefund =
  | { ok: true; amount: number; balance: number; userId: string }
  | { ok: false; code: 'NOT_FOUND' | 'NOT_ORPHAN' | 'TOO_RECENT' | 'ALREADY_REFUNDED' | 'BAD_AMOUNT'; error: string }

/**
 * Admin refund of one orphan wallet prepayment (a debit source 'ride' that no
 * booking ever claimed): the ones the automatic sweep leaves alone — older than
 * ORPHAN_HORIZON_MS, or parked as 'orphan-review' because an unlinked ride was
 * near — and a sweep claim ('orphan-refund') whose credit never landed.
 *
 * The same two claims as sweepOrphanPrepayments, so the two can never both pay:
 *   1. the row flips ref ('' | 'orphan-review') → 'orphan-refund' atomically —
 *      linkWallet flips ref '' → rideId on the same row, so a debit is linked
 *      or refunded, never both;
 *   2. the credit claims `refund:orphan:<txId>` on the rider in the same
 *      update that adds the money — the token the sweep uses — so a retry, a
 *      double click or a sweep racing this refunds nothing more.
 * A ref '' debit younger than the sweep's own window is refused (TOO_RECENT):
 * it may still be linked to a booking being made.
 */
export async function refundOrphanWalletDebit(txId: string, nowMs = Date.now()): Promise<OrphanAdminRefund> {
  const tx: any = await WalletTransaction.findById(txId).lean()
  if (!tx) return { ok: false, code: 'NOT_FOUND', error: 'Transaction not found' }
  if (tx.type !== 'debit' || tx.source !== 'ride' || !ADMIN_ORPHAN_REFS.includes(String(tx.ref ?? ''))) {
    return { ok: false, code: 'NOT_ORPHAN', error: 'This debit is tied to a ride or was already handled' }
  }
  if (String(tx.ref ?? '') === '' && new Date(tx.createdAt).getTime() > nowMs - ORPHAN_WALLET_MS) {
    return { ok: false, code: 'TOO_RECENT', error: 'Too recent: it may still be linked to a booking' }
  }
  const row: any = await WalletTransaction.findOneAndUpdate(
    { _id: tx._id, type: 'debit', source: 'ride', ref: { $in: ADMIN_ORPHAN_REFS } },
    { $set: { ref: 'orphan-refund' } }, { new: true },
  ).lean()
  if (!row || !row.userId) return { ok: false, code: 'NOT_ORPHAN', error: 'This debit is tied to a ride or was already handled' }
  const amount = Math.round((Number(row.amount) || 0) * 100) / 100
  if (amount <= 0) return { ok: false, code: 'BAD_AMOUNT', error: 'Nothing to refund' }
  const c = await credit(String(row.userId), amount, `refund:orphan:${row._id}`, `refund:orphan:${row._id}`, 'wallet',
    'Refund: an outstation prepayment that was not used for a booking')
  if (!c) return { ok: false, code: 'ALREADY_REFUNDED', error: 'Already refunded' }
  return { ok: true, amount: c.amount, balance: c.balance, userId: String(row.userId) }
}

export type OrphanSweep = { walletRefunded: number; onlineRefunded: number; linked: number; amount: number }

/**
 * Gives back prepayments that never backed a booking (run by POST
 * /api/cron/payments and the dispatch cron):
 *   (a) wallet debits source 'ride' ref '' older than 15 minutes — claimed by
 *       flipping ref '' → 'orphan-refund' atomically; linkWallet claims the
 *       same row by flipping ref '' → rideId, so only one of them can win;
 *   (b) Razorpay outstation prepayments seen via the webhook that no ride linked
 *       within 30 minutes — refunded by claiming `prepay:<paymentId>` on the
 *       rider, the token linkOnline / refundRefusedPrepayment claim too, so a
 *       payment is linked or refunded, never both.
 * Every refund is a wallet credit (source 'refund'). Never throws.
 */
export async function sweepOrphanPrepayments(limit = 50, nowMs = Date.now()): Promise<OrphanSweep> {
  const out: OrphanSweep = { walletRefunded: 0, onlineRefunded: 0, linked: 0, amount: 0 }
  try {
    const rows: any[] = await WalletTransaction.find({
      type: 'debit', source: 'ride', ref: '',
      createdAt: { $lt: new Date(nowMs - ORPHAN_WALLET_MS), $gte: new Date(nowMs - ORPHAN_HORIZON_MS) },
    }).select('_id userId createdAt').limit(limit).lean()
    for (const r of rows) {
      try {
        if (await unlinkedRideNear(r.userId, r.createdAt)) {
          await WalletTransaction.updateOne({ _id: r._id, ref: '' }, { $set: { ref: 'orphan-review' } })
          continue
        }
        const row: any = await WalletTransaction.findOneAndUpdate(
          { _id: r._id, ref: '' }, { $set: { ref: 'orphan-refund' } }, { new: true },
        ).lean()
        if (!row || !row.userId) continue
        const amount = Math.round((Number(row.amount) || 0) * 100) / 100
        if (amount <= 0) continue
        const c = await credit(String(row.userId), amount, `refund:orphan:${row._id}`, `refund:orphan:${row._id}`, 'wallet',
          'Refund: an outstation prepayment that was not used for a booking')
        if (c) { out.walletRefunded++; out.amount += c.amount }
      } catch (e) { console.error('[prepay] orphan wallet refund failed', e) }
    }

    const lease = new Date(nowMs - 60_000)
    const open: any[] = await RazorpayPrepay.find({
      state: 'open', createdAt: { $lt: new Date(nowMs - ORPHAN_ONLINE_MS) },
    }).select('_id').limit(limit).lean()
    for (const o of open) {
      try {
        const doc: any = await RazorpayPrepay.findOneAndUpdate(
          { _id: o._id, state: 'open', $or: [{ leaseAt: null }, { leaseAt: { $lt: lease } }] },
          { $set: { leaseAt: new Date(nowMs) } }, { new: true },
        ).lean()
        if (!doc) continue
        const ride: any = await Ride.findOne({ prepaidRef: doc.paymentId }).select('_id').lean()
        if (ride) {
          await RazorpayPrepay.updateOne({ _id: doc._id }, { $set: { state: 'linked', rideId: ride._id } })
          out.linked++
          continue
        }
        if (await unlinkedRideNear(doc.userId, doc.createdAt)) {
          await RazorpayPrepay.updateOne({ _id: doc._id }, { $set: { state: 'skipped' } })
          continue
        }
        const c = await credit(String(doc.userId), Number(doc.amount) || 0, prepayToken(doc.paymentId), `refund:orphan:${doc.paymentId}`, 'online',
          'Refund: an outstation payment that was not used for a booking')
        if (c) {
          await RazorpayPrepay.updateOne({ _id: doc._id }, { $set: { state: 'refunded', refundedAt: new Date() } })
          out.onlineRefunded++; out.amount += c.amount
        } else {
          // The token was already claimed: linked to a booking (possibly one
          // being created right now) or refunded by a refused booking.
          await RazorpayPrepay.updateOne({ _id: doc._id }, { $set: { state: 'skipped' } })
        }
      } catch (e) { console.error('[prepay] orphan online refund failed', e) }
    }
  } catch (e) {
    console.error('[prepay] orphan sweep failed', e)
  }
  out.amount = Math.round(out.amount * 100) / 100
  return out
}
