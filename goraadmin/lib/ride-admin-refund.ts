// ─────────────────────────────────────────────────────────────────────────────
// Admin "Refund this ride" (POST /api/rides/{id}/admin { action: 'refund' }).
//
// Credits the RIDER's Gora wallet (User.walletBalance + a WalletTransaction
// credit, source 'refund', ref `refund:<rideId>:admin:<key>`) with at most
//
//     refundable = paid − refunded
//
// where, for this ride and this rider only:
//   paid     = wallet debits tied to the ride (source 'ride', ref <rideId> or
//              'void:<rideId>' — the wallet prepayment, /complete's debit,
//              /wallet/pay, and a voided double payment)
//            + an online prepayment (prepaidVia 'online': what was captured)
//            + a SETTLED online ride payment (onlinePayment.settled)
//            + cash collected on a completed cash ride (amountDue, paid)
//   refunded = every refund credit to the rider for this ride: the automatic
//              cancel refunds (refund:<id>:prepaid / :ridedebit: / :walletpay:),
//              earlier admin refunds (refund:<id>:admin:*), the booking-time
//              prepay excess (refund:prepay-excess:<prepaidRef>) and online
//              payment returns (refund:ridepay:<paymentId>).
// Co-riders' split shares are not the rider's money and are left out of both.
//
// Automatic refunds come first: the refund is refused while they can still
// run — a ride that is not completed / cancelled, a cancelled ride whose
// refund is still pending, or an online payment not yet settled — so an admin
// refund can never be followed by an automatic one for the same money.
//
// Gora pays it: the driver's wallet is NOT debited. Idempotent per request:
// the client sends a key; the same key never credits twice (the token is
// claimed on the user in the same update that adds the money). A lease on the
// ride stops two different requests both passing the cap at once.
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

export const ADMIN_REFUND_LEASE_MS = 30_000
const r2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100
const escRx = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

export type RefundSummary = {
  paid: number
  refunded: number
  refundable: number
  parts: { label: string; amount: number }[]
  refunds: { ref: string; amount: number; note: string; at: any }[]
  blocked?: string
}

export async function refundSummaryFor(ride: any): Promise<RefundSummary> {
  const id = String(ride._id)
  const parts: { label: string; amount: number }[] = []
  let paid = 0
  const add = (label: string, amount: number) => { const a = r2(amount); if (a > 0) { parts.push({ label, amount: a }); paid += a } }

  let refunds: any[] = []
  if (ride.riderId) {
    const debits: any[] = await WalletTransaction.find({
      userId: ride.riderId, type: 'debit', source: 'ride', ref: { $in: [id, `void:${id}`] },
    }).select('amount ref').lean()
    add('Wallet payments', debits.reduce((s, d) => s + (Number(d.amount) || 0), 0))

    const pids = [ride.onlinePayment?.paymentId, ride.prepaidVia === 'online' ? ride.prepaidRef : null].filter(Boolean).map(String)
    const exact = [
      ...pids.map(p => `refund:ridepay:${p}`),
      ...(ride.prepaidRef ? [`refund:prepay-excess:${ride.prepaidRef}`] : []),
    ]
    refunds = await WalletTransaction.find({
      userId: ride.riderId, type: 'credit', source: 'refund',
      $or: [{ ref: { $regex: `^refund:${escRx(id)}:(?!split:)` } }, ...(exact.length ? [{ ref: { $in: exact } }] : [])],
    }).select('amount ref note createdAt').sort({ createdAt: 1 }).lean()
  }
  if (ride.prepaidVia === 'online' && ride.prepaidRef) add('Online prepayment', Number(ride.prepaidCaptured) || Number(ride.prepaidAmount) || 0)
  if (ride.onlinePayment?.settled) add('Online payment', Number(ride.onlinePayment.amount) || 0)
  if (ride.status === 'completed' && ride.paymentMode === 'cash' && ride.paymentStatus === 'paid') add('Cash to driver', Number(ride.amountDue) || 0)

  paid = r2(paid)
  const refunded = r2(refunds.reduce((s, x) => s + (Number(x.amount) || 0), 0))
  let blocked: string | undefined
  if (!['completed', 'cancelled'].includes(ride.status)) blocked = 'Only a completed or cancelled ride can be refunded'
  else if (ride.status === 'cancelled' && ride.refundPending) blocked = 'The automatic cancel refund has not finished yet — try again in a minute'
  else if (ride.onlinePayment?.paymentId && !ride.onlinePayment.settled) blocked = 'An online payment on this ride is still being settled'
  else if (!ride.riderId) blocked = 'This ride has no rider account'
  return {
    paid, refunded, refundable: Math.max(0, r2(paid - refunded)), parts,
    refunds: refunds.map(x => ({ ref: x.ref, amount: x.amount, note: x.note, at: x.createdAt })),
    ...(blocked ? { blocked } : {}),
  }
}

export type AdminRefundResult =
  | { ok: true; amount: number; balance: number; duplicate?: boolean; summary: RefundSummary }
  | { ok: false; status: number; error: string; code: string; refundable?: number }

export async function adminRefundRide(rideId: string, opts: { amount: number; reason: string; key: string }): Promise<AdminRefundResult> {
  const key = String(opts.key || '')
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(key)) return { ok: false, status: 400, error: 'A request key (8–64 letters, digits, - or _) is required', code: 'KEY_REQUIRED' }
  const reason = String(opts.reason || '').trim()
  if (reason.length < 5 || reason.length > 300) return { ok: false, status: 400, error: 'Give a reason (5–300 characters)', code: 'REASON_REQUIRED' }
  const amount = r2(Number(opts.amount))
  if (!(amount > 0)) return { ok: false, status: 400, error: 'Amount must be more than ₹0', code: 'BAD_AMOUNT' }

  const ref = `refund:${rideId}:admin:${key}`
  const token = `admin-refund:${rideId}:${key}`
  const dup = async (): Promise<AdminRefundResult | null> => {
    const prev: any = await WalletTransaction.findOne({ ref }).select('amount balanceAfter').lean()
    if (!prev) return null
    const ride: any = await Ride.findById(rideId).lean()
    return { ok: true, duplicate: true, amount: prev.amount, balance: prev.balanceAfter, summary: await refundSummaryFor(ride) }
  }
  const d0 = await dup(); if (d0) return d0

  const now = new Date()
  const leased: any = await Ride.findOneAndUpdate(
    { _id: rideId, $or: [{ adminRefundLeaseAt: null }, { adminRefundLeaseAt: { $lt: new Date(now.getTime() - ADMIN_REFUND_LEASE_MS) } }] },
    { $set: { adminRefundLeaseAt: now } },
    { new: true },
  ).lean()
  if (!leased) {
    if (!(await Ride.exists({ _id: rideId }))) return { ok: false, status: 404, error: 'Ride not found', code: 'NOT_FOUND' }
    return { ok: false, status: 409, error: 'Another refund of this ride is in progress. Try again in a moment.', code: 'BUSY' }
  }
  try {
    const d1 = await dup(); if (d1) return d1
    const sum = await refundSummaryFor(leased)
    if (sum.blocked) return { ok: false, status: 409, error: sum.blocked, code: 'NOT_REFUNDABLE', refundable: sum.refundable }
    if (amount > sum.refundable + 0.001) {
      return {
        ok: false, status: 400, code: 'EXCEEDS_PAID', refundable: sum.refundable,
        error: `At most ₹${sum.refundable} can be refunded (paid ₹${sum.paid}, already refunded ₹${sum.refunded})`,
      }
    }
    const u: any = await User.findOneAndUpdate(
      { _id: leased.riderId, walletRechargeRefs: { $ne: token } },
      { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: token } },
      { new: true },
    ).select('walletBalance').lean()
    if (!u) {
      if (!(await User.exists({ _id: leased.riderId }))) return { ok: false, status: 404, error: "The rider's account no longer exists", code: 'NO_RIDER' }
      const d2 = await dup(); if (d2) return d2
      return { ok: false, status: 409, error: 'This request was already applied', code: 'DUPLICATE' }
    }
    await WalletTransaction.create({
      userId: leased.riderId, type: 'credit', amount, balanceAfter: u.walletBalance || 0,
      note: `Refund for your ${leased.service || 'ride'}: ${reason}`.slice(0, 300), source: 'refund', ref,
    })
    await Ride.updateOne({ _id: leased._id }, { $inc: { adminRefundTotal: amount } })
    const after: any = await Ride.findById(rideId).lean()
    return { ok: true, amount, balance: u.walletBalance || 0, summary: await refundSummaryFor(after) }
  } finally {
    await Ride.updateOne({ _id: rideId, adminRefundLeaseAt: now }, { $unset: { adminRefundLeaseAt: 1 } }).catch(() => {})
  }
}
