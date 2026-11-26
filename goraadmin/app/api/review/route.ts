export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import User from '@/models/User'
import Withdrawal from '@/models/Withdrawal'
import WalletTransaction from '@/models/WalletTransaction'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'
import { parsePaging } from '@/lib/list-params'
import { ORPHAN_HORIZON_MS, ORPHAN_ONLINE_MS, refundOrphanWalletDebit } from '@/lib/prepay'

// ─────────────────────────────────────────────────────────────────────────────
// "Needs review" queue for the admin panel (app/(dashboard)/review).
//
// GET ?tab=rides|cod|refunds|withdrawals&page&limit
//   ← { counts: { rides, cod, refunds, withdrawals }, tab, page, limit, total, rows,
//       orphans?, orphanTotal? (refunds tab) }
//   rides       — needsReview = true (stuck, rider reports, refund_stuck, …)
//   cod         — delivery COD still owed by the driver (codPendingRemittance
//                 > 0) that no admin marked settled
//   refunds     — rides with reviewReason 'refund_stuck' still open, or a
//                 refundReview no admin marked handled; plus orphan wallet
//                 prepayments the automatic sweep does not touch (ref '' older
//                 than ORPHAN_HORIZON_MS, or parked as 'orphan-review')
//   withdrawals — pending withdrawals to a bank account added/changed recently
//
// POST (password re-entry, audited):
//   { action: 'cod_settled', rideId, note? }    record only — no wallet moves
//   { action: 'refund_handled', rideId, note? } record only — no wallet moves
//   { action: 'orphan_refund', txId }           wallet credit to the rider,
//                                               once (lib/prepay refundOrphanWalletDebit)
// Every action is idempotent: a repeat answers { already: true } and changes nothing.
// ─────────────────────────────────────────────────────────────────────────────

const TABS = ['rides', 'cod', 'refunds', 'withdrawals'] as const

const ridesFilter = () => ({ needsReview: true })
const codFilter = () => ({ codPendingRemittance: { $gt: 0 }, codRemittedAt: null })
const refundRidesFilter = () => ({
  $or: [
    { needsReview: true, reviewReason: 'refund_stuck' },
    { refundReview: { $nin: [null, ''] }, refundReviewResolvedAt: null },
  ],
})
const orphanFilter = (nowMs = Date.now()) => ({
  type: 'debit', source: 'ride',
  $or: [{ ref: '', createdAt: { $lt: new Date(nowMs - ORPHAN_HORIZON_MS) } }, { ref: 'orphan-review' }],
})
const withdrawalsFilter = () => ({ status: 'pending', bankChangedRecently: true })

const RIDE_FIELDS = '_id status service paymentMode riderId riderName riderPhone driverId driverName driverPhone pickupAddress dropAddress fare totalFare createdAt cancelledAt needsReview needsReviewAt reviewReason stuckSince issueReports refundReview refundPending refundAttempts refundedAmount cancelledFromStatus prepaidAmount prepaidVia prepaidRef prepaidUnlinked codAmount codCollected codSenderCredited codPendingRemittance codSettledAt deliveredAt senderName senderPhone receiverName receiverPhone otpLocked dropOtpLocked deliveryPhase'

const mask = (s: any) => { const v = String(s || ''); return v.length > 4 ? `••••${v.slice(-4)}` : v }

export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const sp = req.nextUrl.searchParams
    const tab = (TABS as readonly string[]).includes(sp.get('tab') || '') ? sp.get('tab')! : 'rides'
    const { page, limit, skip } = parsePaging(sp, 50)
    const now = Date.now()

    const [rides, cod, refundRides, orphans, withdrawals] = await Promise.all([
      Ride.countDocuments(ridesFilter()),
      Ride.countDocuments(codFilter()),
      Ride.countDocuments(refundRidesFilter()),
      WalletTransaction.countDocuments(orphanFilter(now)),
      Withdrawal.countDocuments(withdrawalsFilter()),
    ])
    const counts = { rides, cod, refunds: refundRides + orphans, withdrawals }
    const out: any = { counts, tab, page, limit }

    if (tab === 'rides') {
      out.total = rides
      out.rows = await Ride.find(ridesFilter()).sort({ needsReviewAt: -1, _id: -1 }).skip(skip).limit(limit).select(RIDE_FIELDS).lean()
    } else if (tab === 'cod') {
      out.total = cod
      out.rows = await Ride.find(codFilter()).sort({ codSettledAt: 1, _id: 1 }).skip(skip).limit(limit).select(RIDE_FIELDS).lean()
    } else if (tab === 'refunds') {
      out.total = refundRides
      out.rows = await Ride.find(refundRidesFilter()).sort({ createdAt: -1 }).skip(skip).limit(limit).select(RIDE_FIELDS).lean()
      out.orphanTotal = orphans
      const txs: any[] = await WalletTransaction.find(orphanFilter(now)).sort({ createdAt: 1 }).skip(skip).limit(limit).lean()
      const users: any[] = await User.find({ _id: { $in: txs.map(t => t.userId).filter(Boolean) } }).select('name phone walletBalance').lean()
      const byId = new Map(users.map(u => [String(u._id), u]))
      out.orphans = await Promise.all(txs.map(async t => {
        const at = new Date(t.createdAt).getTime()
        // The unlinked prepaid rides near this payment — the reason the sweep
        // parked it. The admin checks them before refunding.
        const near: any[] = t.userId ? await Ride.find({
          riderId: t.userId, prepaidUnlinked: true,
          createdAt: { $gte: new Date(at - 5 * 60_000), $lte: new Date(at + ORPHAN_ONLINE_MS) },
        }).select('_id status').limit(5).lean() : []
        const u = byId.get(String(t.userId))
        return {
          _id: t._id, userId: t.userId, userName: u?.name || '', userPhone: u?.phone || '',
          amount: t.amount, note: t.note, ref: t.ref, createdAt: t.createdAt,
          nearbyUnlinkedRides: near.map(r => ({ _id: r._id, status: r.status })),
        }
      }))
    } else {
      out.total = withdrawals
      const rows: any[] = await Withdrawal.find(withdrawalsFilter()).sort({ createdAt: 1 }).skip(skip).limit(limit).lean()
      out.rows = rows.map(w => ({
        _id: w._id, driverId: w.driverId, driverName: w.driverName, driverPhone: w.driverPhone,
        amount: w.amount, bankName: w.bankName, accountHolderName: w.accountHolderName,
        accountNumber: mask(w.accountNumber), createdAt: w.createdAt, status: w.status,
      }))
    }
    return NextResponse.json(out)
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  const needPwd = await requireAdminPassword(req); if (needPwd) return needPwd
  try {
    const admin: any = requireAdmin(req)
    const by = String(admin?.email || admin?.id || '')
    const b = await req.json().catch(() => ({}))
    const action = String(b?.action || '')
    const note = typeof b?.note === 'string' ? b.note.trim().slice(0, 500) : ''
    await connectDB()

    if (action === 'cod_settled' || action === 'refund_handled') {
      const rideId = String(b?.rideId || '')
      if (!mongoose.isValidObjectId(rideId)) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
      const now = new Date()
      const [filter, set, auditName] = action === 'cod_settled'
        ? [{ _id: rideId, codPendingRemittance: { $gt: 0 }, codRemittedAt: null },
          { codRemittedAt: now, codRemittedBy: by, codRemittedNote: note }, 'ride.cod.settled']
        : [{ _id: rideId, refundReview: { $nin: [null, ''] }, refundReviewResolvedAt: null },
          { refundReviewResolvedAt: now, refundReviewResolvedBy: by, refundReviewNote: note }, 'ride.refund_review.handled']
      // Claimed in one update: a double click or two admins record it once.
      const r: any = await Ride.findOneAndUpdate(filter as any, { $set: set }, { new: true })
        .select('_id codPendingRemittance codRemittedAt codRemittedBy refundReview refundReviewResolvedAt refundReviewResolvedBy riderName driverName').lean()
      if (!r) {
        const cur: any = await Ride.findById(rideId).select('_id codPendingRemittance codRemittedAt codRemittedBy refundReview refundReviewResolvedAt refundReviewResolvedBy').lean()
        if (!cur) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
        const done = action === 'cod_settled' ? cur.codRemittedAt : cur.refundReviewResolvedAt
        if (done) {
          return NextResponse.json({ success: true, already: true, at: done, by: action === 'cod_settled' ? cur.codRemittedBy : cur.refundReviewResolvedBy })
        }
        return NextResponse.json({ error: action === 'cod_settled' ? 'No COD pending on this ride' : 'This ride has no refund review' }, { status: 409 })
      }
      await auditAdmin(req, admin, auditName, {
        target: `ride:${rideId}`,
        summary: action === 'cod_settled'
          ? `COD ₹${r.codPendingRemittance} marked settled (driver ${r.driverName || '—'} → sender ${r.riderName || '—'})`
          : `Refund review '${r.refundReview}' marked handled`,
        details: { note, ...(action === 'cod_settled' ? { amount: r.codPendingRemittance } : { refundReview: r.refundReview }) },
      })
      return NextResponse.json({ success: true, already: false })
    }

    if (action === 'orphan_refund') {
      const txId = String(b?.txId || '')
      if (!mongoose.isValidObjectId(txId)) return NextResponse.json({ error: 'Transaction not found' }, { status: 404 })
      const res = await refundOrphanWalletDebit(txId)
      if (!res.ok) {
        if (res.code === 'ALREADY_REFUNDED') return NextResponse.json({ success: true, already: true })
        const status = res.code === 'NOT_FOUND' ? 404 : 409
        return NextResponse.json({ error: res.error, code: res.code }, { status })
      }
      await auditAdmin(req, admin, 'wallet.orphan.refund', {
        target: `user:${res.userId}`,
        summary: `Refunded orphan prepayment ₹${res.amount} to wallet (tx ${txId})`,
        details: { txId, amount: res.amount, balanceAfter: res.balance, note },
      })
      return NextResponse.json({ success: true, already: false, amount: res.amount, balance: res.balance })
    }

    return NextResponse.json({ error: "action must be 'cod_settled', 'refund_handled' or 'orphan_refund'" }, { status: 400 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
