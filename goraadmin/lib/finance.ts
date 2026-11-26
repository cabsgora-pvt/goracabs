// ─────────────────────────────────────────────────────────────────────────────
// One definition of the money figures shown in the admin (finance summary,
// finance reports, dashboard), so the pages stop disagreeing with each other.
//
//   • Days and months are India time (IST, +05:30) whatever the server's own
//     timezone (UTC on the VPS).
//   • A completed ride counts in the period it was COMPLETED (completedAt), for
//     the amount it was billed (totalFare, falling back to fare on old rides).
//   • Revenue / commission / driver payout count only rides whose payment was
//     COLLECTED (paymentStatus 'paid'). Completed rides still waiting for an
//     online payment are reported separately as pending.
//   • Subscription revenue = DriverSubscription.price, by purchase time.
//   • Cancellation fees collected = the part of a prepaid booking kept when the
//     rider cancelled (lib/refunds.ts keeps min(fee, prepaid)); a fee on a ride
//     with nothing prepaid is only charged on paper (cancellationFeesCharged).
//   • Refunds = wallet credits with source 'refund'. Only refunds of money
//     from a COMPLETED ride reduce collected revenue (refundsOnCompletedRides);
//     refunds of prepaid bookings / duplicate online payments return money that
//     never counted as revenue, so they are shown but not netted.
//   • Franchise share (the zone admin's part) is deducted from Gora's net for
//     both ride commission and subscriptions, as fixed on each record.
//   • Coupon cost: Gora funds coupons (commission stays on the full fare, the
//     rider pays less, and on cash rides Gora credits the discount back to the
//     driver). The discount actually given on PAID rides — pendingCoupon, the
//     amount settlement took off (older rides: couponDiscount) — is reported as
//     couponCost and comes off netCollectedRevenue and platformNet. A rental's
//     coupon is already off its fare, so it is not a separate cost.
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import DriverSubscription from '@/models/DriverSubscription'
import WalletTransaction from '@/models/WalletTransaction'
import mongoose from 'mongoose'

export const IST_MS = 5.5 * 3600e3
const DAY_MS = 864e5

/** IST midnight `daysAgo` days before today, as a UTC Date. */
export function istMidnight(daysAgo = 0, nowMs = Date.now()): Date {
  return new Date(Math.floor((nowMs + IST_MS) / DAY_MS) * DAY_MS - IST_MS - daysAgo * DAY_MS)
}

/** First day of the current IST month, 00:00 IST. */
export function istMonthStart(nowMs = Date.now()): Date {
  const d = new Date(nowMs + IST_MS)
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) - IST_MS)
}

/** 'YYYY-MM-DD' → that day's 00:00 IST. Anything else → null. */
export function istDayStart(ymd: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(ymd || ''))
  if (!m) return null
  const t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) - IST_MS
  return Number.isFinite(t) ? new Date(t) : null
}

export type Range = { from?: Date | null; to?: Date | null }   // [from, to)

/** Range for a dateFrom..dateTo pair of IST calendar days, both inclusive. */
export function istRange(dateFrom?: string | null, dateTo?: string | null): Range {
  const from = dateFrom ? istDayStart(dateFrom) : null
  const toDay = dateTo ? istDayStart(dateTo) : null
  return { from, to: toDay ? new Date(toDay.getTime() + DAY_MS) : null }
}

function within(range: Range | undefined): any {
  const r: any = {}
  if (range?.from) r.$gte = range.from
  if (range?.to) r.$lt = range.to
  return Object.keys(r).length ? r : undefined
}

export const FARE_EXPR = { $ifNull: ['$totalFare', { $ifNull: ['$fare', 0] }] }

/** $match for completed rides in a range (by completedAt). */
export function completedMatch(range?: Range, extra: any = {}): any {
  const m: any = { status: 'completed', ...extra }
  const w = within(range)
  if (w) m.completedAt = w
  return m
}

export const PAID = { paymentStatus: 'paid' }
export const UNPAID = { paymentStatus: { $ne: 'paid' } }

export type FinanceTotals = {
  completedRides: number
  bookedRevenue: number            // every completed ride, paid or not
  collectedRides: number
  collectedRevenue: number         // paid rides only
  commission: number               // on paid rides
  driverPayout: number             // driverEarning on paid rides
  rideFranchiseShare: number       // zone admins' part of that commission
  pendingRides: number
  pendingRevenue: number           // completed, payment not collected yet
  pendingOnlineRides: number
  pendingOnlineRevenue: number     // …of which online/wallet
  subscriptionCount: number
  subscriptionRevenue: number
  subscriptionFranchiseShare: number
  cancellationFeesCharged: number
  cancellationFeesCollected: number
  refunds: number
  refundsOnCompletedRides: number
  couponCost: number               // Gora-funded discounts on paid rides
  netCollectedRevenue: number      // collectedRevenue − refundsOnCompletedRides − couponCost
  platformNet: number              // Gora's own: commission + subs + fees − franchise − refunds on completed rides − couponCost
}

const round2 = (n: number) => Math.round((Number(n) || 0) * 100) / 100

// Optional zone scope (additive): rides and cancellations by Ride.zoneId,
// subscriptions by DriverSubscription.zoneId, and only refunds whose ref names
// a ride of that zone. Without it the totals are platform-wide, as before.
export async function financeTotals(range?: Range, opts: { zoneId?: string } = {}): Promise<FinanceTotals> {
  const w = within(range)
  const zid = opts.zoneId && mongoose.isValidObjectId(opts.zoneId) ? new mongoose.Types.ObjectId(opts.zoneId) : null
  const z = zid ? { zoneId: zid } : {}
  const [rideAgg, subAgg, cancelAgg, refundRows] = await Promise.all([
    Ride.aggregate([
      { $match: completedMatch(range, z) },
      {
        $group: {
          _id: null,
          n: { $sum: 1 },
          booked: { $sum: FARE_EXPR },
          paidN: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, 1, 0] } },
          paid: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, FARE_EXPR, 0] } },
          commission: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, { $ifNull: ['$commissionAmount', 0] }, 0] } },
          payout: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, { $ifNull: ['$driverEarning', 0] }, 0] } },
          franchise: { $sum: { $cond: [{ $eq: ['$paymentStatus', 'paid'] }, { $ifNull: ['$franchiseShare.amount', 0] }, 0] } },
          coupon: {
            $sum: {
              $cond: [
                { $and: [{ $eq: ['$paymentStatus', 'paid'] }, { $ne: ['$service', 'rental'] }] },
                { $max: [0, { $ifNull: ['$pendingCoupon', { $ifNull: ['$couponDiscount', 0] }] }] },
                0,
              ],
            },
          },
          pendOnlineN: { $sum: { $cond: [{ $and: [{ $ne: ['$paymentStatus', 'paid'] }, { $in: ['$paymentMode', ['online', 'wallet']] }] }, 1, 0] } },
          pendOnline: { $sum: { $cond: [{ $and: [{ $ne: ['$paymentStatus', 'paid'] }, { $in: ['$paymentMode', ['online', 'wallet']] }] }, FARE_EXPR, 0] } },
        },
      },
    ]),
    DriverSubscription.aggregate([
      { $match: { ...(w ? { createdAt: w } : {}), ...z } },
      { $group: { _id: null, n: { $sum: 1 }, revenue: { $sum: { $ifNull: ['$price', 0] } }, franchise: { $sum: { $ifNull: ['$franchiseShare.amount', 0] } } } },
    ]),
    // A cancelled ride has no cancelledAt; updatedAt is when it was cancelled
    // (the refund sweep touches it right after).
    Ride.aggregate([
      { $match: { status: 'cancelled', cancellationFee: { $gt: 0 }, ...(w ? { updatedAt: w } : {}), ...z } },
      {
        $group: {
          _id: null,
          charged: { $sum: '$cancellationFee' },
          collected: {
            $sum: {
              $cond: [
                { $ne: ['$cancelledFromStatus', 'ongoing'] },
                { $min: ['$cancellationFee', { $ifNull: ['$prepaidAmount', 0] }] },
                0,
              ],
            },
          },
        },
      },
    ]),
    WalletTransaction.find({ source: 'refund', type: 'credit', ...(w ? { createdAt: w } : {}) }).select('amount ref').lean(),
  ])

  const r = rideAgg[0] || {}
  const s = subAgg[0] || {}
  const c = cancelAgg[0] || {}

  // Refunds that give back money from a completed ride: their ref names it.
  const idOf = (ref: string) => (/\b([a-f0-9]{24})\b/i.exec(ref || '') || [])[1]
  let refundList = refundRows as any[]
  if (zid) {
    const refIds = Array.from(new Set(refundList.map(x => idOf(x.ref)).filter(Boolean))) as string[]
    const inZone = new Set(refIds.length ? (await Ride.find({ _id: { $in: refIds }, zoneId: zid }).select('_id').lean()).map((x: any) => String(x._id)) : [])
    refundList = refundList.filter(x => { const id = idOf(x.ref); return id && inZone.has(id) })
  }
  const refunds = refundList.reduce((t, x) => t + (Number(x.amount) || 0), 0)
  const ids = Array.from(new Set(refundList.map(x => idOf(x.ref)).filter(Boolean))) as string[]
  let refundsOnCompletedRides = 0
  if (ids.length) {
    const done = new Set((await Ride.find({ _id: { $in: ids }, status: 'completed' }).select('_id').lean()).map((x: any) => String(x._id)))
    refundsOnCompletedRides = refundList
      .filter(x => { const id = idOf(x.ref); return id && done.has(id) })
      .reduce((t, x) => t + (Number(x.amount) || 0), 0)
  }

  const collectedRevenue = round2(r.paid)
  const commission = round2(r.commission)
  const rideFranchiseShare = round2(r.franchise)
  const subscriptionRevenue = round2(s.revenue)
  const subscriptionFranchiseShare = round2(s.franchise)
  const cancellationFeesCollected = round2(c.collected)
  const couponCost = round2(r.coupon)
  return {
    completedRides: r.n || 0,
    bookedRevenue: round2(r.booked),
    collectedRides: r.paidN || 0,
    collectedRevenue,
    commission,
    driverPayout: round2(r.payout),
    rideFranchiseShare,
    pendingRides: (r.n || 0) - (r.paidN || 0),
    pendingRevenue: round2((r.booked || 0) - (r.paid || 0)),
    pendingOnlineRides: r.pendOnlineN || 0,
    pendingOnlineRevenue: round2(r.pendOnline),
    subscriptionCount: s.n || 0,
    subscriptionRevenue,
    subscriptionFranchiseShare,
    cancellationFeesCharged: round2(c.charged),
    cancellationFeesCollected,
    refunds: round2(refunds),
    refundsOnCompletedRides: round2(refundsOnCompletedRides),
    couponCost,
    netCollectedRevenue: round2(collectedRevenue - refundsOnCompletedRides - couponCost),
    platformNet: round2(commission - rideFranchiseShare + subscriptionRevenue - subscriptionFranchiseShare + cancellationFeesCollected - refundsOnCompletedRides - couponCost),
  }
}
