// ─────────────────────────────────────────────────────────────────────────────
// Ride settlement — the ONE place where a finished ride moves money.
//
// Used by /rides/:id/complete (driver, rider for online rides, admin
// force-complete), /payment/razorpay/verify (a verified online payment) and
// /rides/:id/collect-cash (driver takes cash for an unpaid online ride).
//
// Rules
//   • A ride is completed only from status 'ongoing', by one atomic claim, so a
//     retried/doubled End, or an End racing a cancel, settles at most once.
//   • What the rider owes (riderAmountDue) is computed on the server:
//       billable (service final amount, else booked fare) + waiting charge
//       − split shares already collected + tip − server coupon discount
//       − anything prepaid at booking (outstation).
//   • cash    → the driver collected amountDue; the driver's wallet is debited
//               the commission and credited back the coupon discount (Gora
//               funds coupons: commission stays on the full fare).
//   • wallet  → the RIDER's wallet is debited amountDue atomically ($gte), then
//               the driver is credited their earning. Short wallet → the ride
//               switches to cash and is settled as a cash ride.
//   • online  → completed with paymentStatus 'pending'; the driver is NOT paid
//               until a verified Razorpay payment for this ride arrives
//               (settleOnlinePayment) or the driver takes cash (collectCash).
//   • outstation charged at booking → already paid; driver credited as online.
//               If the prepayment does not cover what is due at the end (extras,
//               an old booking that prepaid without the tip), the driver is
//               credited only what the prepayment covers and the SHORTFALL is
//               left due (paymentStatus 'pending', prepaidShortfall) — paid by
//               the rider online / from the wallet, or taken in cash.
//   • Money inputs are clamped: a non-finite or negative fare/tip/waiting/
//     coupon counts as 0, so a corrupt ride can never push NaN into a wallet.
//   • Only the assigned driver ends a ride; a rider may end only an online,
//     non-prepaid TAXI ride (rental/hire/delivery/outstation bill extras the
//     driver records, so the rider ending first would skip them).
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Transaction from '@/models/Transaction'
import WalletTransaction from '@/models/WalletTransaction'
import { commissionPercentFor, franchiseShareFor } from './commission'
import { chargedAtBooking } from './prepay'
import { distanceKm } from './geo'
import Settings from '@/models/Settings'

/** Rupee tolerance when comparing a gateway amount with what is due. */
export const PAY_TOLERANCE = 1

/** A money input as a finite, non-negative number (anything else → 0). */
export function money(v: unknown): number {
  const n = Number(v)
  return Number.isFinite(n) && n > 0 ? n : 0
}

function serviceFinalOf(ride: any): number {
  return ride.service === 'rental' ? money(ride.finalFare)
    : ride.service === 'hire_driver' ? money(ride.hireFinalFare)
    : ride.service === 'delivery' ? money(ride.deliveryFinalFare)
    : 0
}

/** The coupon discount still to come off what the rider pays. A rental's fare
 *  already has it taken off at booking, so it is never subtracted again. */
export function couponOffOf(ride: any): number {
  if (ride.service === 'rental') return 0
  return money(ride.couponDiscount)
}

export type Figures = {
  fare: number            // full amount for records (base + tip)
  baseFare: number        // commissionable amount (billable + waiting)
  tip: number
  splitCollected: number
  splitCommission: number
  remainingBase: number
  commission: number      // on the not-yet-settled portion
  driverEarning: number   // remainingBase − commission + tip
  coupon: number          // discount actually given on this settlement
  prepaid: number
  amountDue: number       // what the rider still has to pay
}

/** Pure arithmetic of a settlement at `commissionPercent`. */
export function figuresFor(ride: any, commissionPercent: number): Figures {
  const sf = serviceFinalOf(ride)
  const billable = sf > 0 ? sf : money(ride.fare)
  const waiting = money(ride.waitingChargeTotal)
  const tip = money(ride.tip)
  const baseFare = billable + waiting
  const fare = baseFare + tip
  const splitCollected = Math.min(money(ride.splitCollected), baseFare)
  const splitCommission = money(ride.splitCommission)
  const remainingBase = baseFare - splitCollected
  const commission = Math.round((remainingBase * commissionPercent) / 100)
  const driverEarning = (remainingBase - commission) + tip
  const coupon = Math.min(couponOffOf(ride), Math.max(0, remainingBase))
  const prepaid = chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))
    ? money(ride.prepaidAmount) : 0
  const amountDue = Math.max(0, Math.round(remainingBase + tip - coupon - prepaid))
  return { fare, baseFare, tip, splitCollected, splitCommission, remainingBase, commission, driverEarning, coupon, prepaid, amountDue }
}

/** What the rider owes on this ride (commission-independent). */
export function riderAmountDue(ride: any): number {
  return figuresFor(ride, 0).amountDue
}

/**
 * The exact cash a driver must take from the rider for a cash ride right now:
 * billable (service final amount incl. rental/hire/delivery extras, else the
 * booked fare) + waiting + tip − coupon − split shares already paid − anything
 * prepaid. Tolls are not in it (the rider pays those to the driver directly).
 * Rental/hire 'end' responses should show this figure so the app and the
 * settlement never disagree.
 */
export function cashDueFor(ride: any): number {
  return riderAmountDue(ride)
}

export type Actor = { kind: 'driver' | 'rider' | 'admin'; id: string }

export type SettleResult = { status: number; body: any }

async function creditDriver(ride: any, driverId: any, earning: number, mode: string, fare: number, commission: number) {
  const updated: any = await Driver.findByIdAndUpdate(driverId,
    { $inc: { walletBalance: earning, totalEarnings: earning } }, { new: true }).lean()
  await Transaction.create({
    driverId, rideId: ride._id, type: 'ride_earning',
    amount: earning, paymentMode: mode,
    description: `Earning on ${mode} ride ₹${fare} (admin took ₹${commission})`,
    balanceAfter: updated?.walletBalance,
  })
  return updated?.walletBalance as number | undefined
}

async function settleCashOnDriver(ride: any, driverId: any, f: { commission: number; coupon: number; driverEarning: number; fare: number }, pct: number) {
  // The driver holds the cash the rider paid (fare − coupon). They owe Gora the
  // commission on the FULL fare, and Gora reimburses the coupon it granted.
  const delta = -f.commission + f.coupon
  const updated: any = await Driver.findByIdAndUpdate(driverId,
    { $inc: { walletBalance: delta, totalEarnings: f.driverEarning } }, { new: true }).lean()
  const after = updated?.walletBalance
  await Transaction.create({
    driverId, rideId: ride._id, type: 'commission',
    amount: -f.commission, paymentMode: 'cash',
    description: `Commission (${pct}%) on cash ride ₹${f.fare}`,
    balanceAfter: f.coupon > 0 ? (after != null ? after - f.coupon : undefined) : after,
  })
  if (f.coupon > 0) {
    await Transaction.create({
      driverId, rideId: ride._id, type: 'ride_earning',
      amount: f.coupon, paymentMode: 'cash',
      description: `Coupon ${ride.couponCode || ''} ₹${f.coupon} reimbursed by Gora (rider paid ₹${f.fare - f.coupon} in cash)`.replace('  ', ' '),
      balanceAfter: after,
    })
  }
  return after as number | undefined
}

/**
 * Complete an ongoing ride and settle it. `actor` must already be
 * authenticated; this checks they are allowed to end THIS ride.
 */
export async function completeRide(rideId: string, actor: Actor, attempt = 0): Promise<SettleResult> {
  const ride: any = await Ride.findById(rideId).lean()
  if (!ride) return { status: 404, body: { error: 'Ride not found' } }

  const prepaid = chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))
  const isDriver = actor.kind === 'driver' && !!ride.driverId && String(ride.driverId) === actor.id
  const isRider = actor.kind === 'rider' && !!ride.riderId && String(ride.riderId) === actor.id
  // A valid token that is not this ride's: 403, never 401 (a 401 makes the
  // driver app sign the driver out).
  if (!isDriver && !isRider && actor.kind !== 'admin') return { status: 403, body: { error: 'Not a participant in this ride', code: 'NOT_PARTICIPANT' } }
  // Installed rider apps end online taxi rides themselves before paying. That
  // stays allowed, but only as "driver ended it": the ride is left unpaid.
  // Rental / hire / delivery / outstation are always ended by the driver: their
  // extras (time, km, waiting) are recorded at the driver's end.
  if (isRider && ((ride.service || 'taxi') !== 'taxi' || ride.paymentMode !== 'online' || prepaid)) {
    return { status: 403, body: { error: 'Only the driver can end this ride', code: 'driverMustEnd' } }
  }

  if (ride.status === 'completed') return { status: 400, body: { error: 'Already completed', paymentStatus: ride.paymentStatus, amountDue: ride.amountDue } }
  if (ride.status !== 'ongoing') {
    return { status: 400, body: { error: `Ride is ${ride.status}; only an ongoing ride can be completed`, code: 'notOngoing', rideStatus: ride.status } }
  }
  if (!ride.driverId) return { status: 400, body: { error: 'Ride has no driver' } }

  const driver: any = await Driver.findById(ride.driverId).lean()
  const commissionPercent = await commissionPercentFor(driver, ride)
  const f = figuresFor(ride, commissionPercent)

  const set: any = {
    status: 'completed', completedAt: new Date(),
    totalFare: f.fare, commissionPercent,
    commissionAmount: f.splitCommission + f.commission,
    driverEarning: (f.splitCollected - f.splitCommission) + f.driverEarning,
    pendingCommission: f.commission, pendingDriverEarning: f.driverEarning, pendingCoupon: f.coupon,
    amountDue: f.amountDue,
    paymentStatus: 'pending',
  }
  if (ride.service === 'outstation') {
    set.outstationPhase = 'completed'
    // Billed at the fixed booked fare wherever it ends; far-off ends are flagged.
    const round = ride.tripType === 'round_trip'
    const endLat = round ? ride.pickupLat : ride.dropLat
    const endLng = round ? ride.pickupLng : ride.dropLng
    if (driver?.currentLat != null && driver?.currentLng != null && endLat != null && endLng != null) {
      const km = distanceKm({ lat: driver.currentLat, lng: driver.currentLng }, { lat: endLat, lng: endLng })
      if (km > 10) set.endedAwayKm = Math.round(km)
    }
  }
  try { set.franchiseShare = await franchiseShareFor(ride.zoneId, set.commissionAmount) } catch (e) { console.error('[complete] franchise share failed', e) }

  // The claim: only the request that flips ongoing → completed settles.
  // Also conditioned on the split total read above: a co-rider paying their
  // share in between would otherwise be settled twice. Then just recompute.
  const splitNow = ride.splitCollected ? ride.splitCollected : { $in: [0, null] }
  const claimed: any = await Ride.findOneAndUpdate({ _id: ride._id, status: 'ongoing', splitCollected: splitNow }, { $set: set }, { new: true }).lean()
  if (!claimed) {
    if (attempt < 3) {
      const st: any = await Ride.findById(ride._id).select('status').lean()
      if (st?.status === 'ongoing') return completeRide(rideId, actor, attempt + 1)
    }
    const now: any = await Ride.findById(ride._id).select('status paymentStatus amountDue').lean()
    if (now?.status === 'completed') return { status: 400, body: { error: 'Already completed', paymentStatus: now.paymentStatus, amountDue: now.amountDue } }
    return { status: 400, body: { error: `Ride is ${now?.status || 'gone'}; only an ongoing ride can be completed`, code: 'notOngoing', rideStatus: now?.status } }
  }
  await Driver.updateOne({ _id: ride.driverId }, { $inc: { totalRides: 1 } })

  let mode: string = ride.paymentMode || 'cash'
  let walletAfter: number | undefined = driver?.walletBalance
  let paymentStatus = 'pending'
  let switched = false
  let riderWalletBalance: number | undefined

  let shortfall = 0
  if (prepaid && f.amountDue <= PAY_TOLERANCE) {
    // Outstation paid in full at booking (book refuses unless verified; a
    // rupee of rounding is not chased).
    walletAfter = await creditDriver(claimed, ride.driverId, f.driverEarning, mode, f.fare, f.commission)
    await Ride.updateOne({ _id: ride._id }, { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date() } })
    paymentStatus = 'paid'
  } else if (prepaid) {
    // The prepayment does not cover everything due. Credit the driver only what
    // it covers (prepaid + Gora's coupon − commission = earning − shortfall);
    // the shortfall stays due and is credited when it is paid (online / wallet)
    // or is already in the driver's hand (cash) — see collectCash.
    shortfall = f.amountDue
    const now = f.driverEarning - shortfall
    if (now > 0) walletAfter = await creditDriver(claimed, ride.driverId, now, mode, f.fare, f.commission)
    else if (now < 0) {
      const u: any = await Driver.findByIdAndUpdate(ride.driverId, { $inc: { walletBalance: now } }, { new: true }).lean()
      walletAfter = u?.walletBalance
      await Transaction.create({
        driverId: ride.driverId, rideId: ride._id, type: 'commission', amount: now, paymentMode: mode,
        description: `Commission not covered by the prepayment on ₹${f.fare}`, balanceAfter: walletAfter,
      })
    }
    await Ride.updateOne({ _id: ride._id }, { $set: {
      prepaidShortfall: true, awaitingPayment: true,
      pendingDriverEarning: shortfall, pendingCommission: 0, pendingCoupon: 0,
    } })
  } else if (mode === 'wallet') {
    let debited = f.amountDue === 0
    if (f.amountDue > 0 && ride.riderId) {
      // Same claim key /wallet/pay takes with its own debit, so an installed
      // rider app paying in the gap after the status flip cannot debit twice:
      // whichever update lands first takes the money, the other sees the key.
      const key = `ride:${String(ride._id)}`
      const u: any = await User.findOneAndUpdate(
        { _id: ride.riderId, walletBalance: { $gte: f.amountDue }, walletRechargeRefs: { $ne: key } },
        { $inc: { walletBalance: -f.amountDue }, $push: { walletRechargeRefs: key } }, { new: true },
      ).select('walletBalance').lean()
      if (!u && await User.exists({ _id: ride.riderId, walletRechargeRefs: key })) {
        // /wallet/pay already took it (and wrote its own WalletTransaction).
        debited = true
      } else if (u) {
        debited = true
        riderWalletBalance = u.walletBalance
        await WalletTransaction.create({
          userId: ride.riderId, type: 'debit', amount: f.amountDue, balanceAfter: u.walletBalance,
          note: `Ride payment (${ride.service || 'ride'})`, source: 'ride', ref: String(ride._id),
        })
      }
    }
    if (debited) {
      walletAfter = await creditDriver(claimed, ride.driverId, f.driverEarning, 'wallet', f.fare, f.commission)
      await Ride.updateOne({ _id: ride._id }, { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), riderWalletDebit: f.amountDue } })
      paymentStatus = 'paid'
    } else {
      // Rider's wallet is short: the driver collects cash instead.
      switched = true
      mode = 'cash'
      await Ride.updateOne({ _id: ride._id }, { $set: { paymentMode: 'cash', paymentSwitchedToCash: true } })
    }
  }

  if (mode === 'cash' && !prepaid) {
    walletAfter = await settleCashOnDriver(claimed, ride.driverId, f, commissionPercent)
    await Ride.updateOne({ _id: ride._id }, { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), ...(f.coupon > 0 ? { couponReimbursed: f.coupon } : {}) } })
    paymentStatus = 'paid'
  } else if (mode === 'online' && !prepaid) {
    await Ride.updateOne({ _id: ride._id }, { $set: { awaitingPayment: f.amountDue > 0 } })
    if (f.amountDue === 0) {
      // Nothing left to pay (split/coupon covered it): settle now.
      const flip = await Ride.updateOne({ _id: ride._id, paymentStatus: 'pending', paymentMode: 'online' }, { $set: { paymentStatus: 'paid', paidAt: new Date() } })
      if (flip.modifiedCount) { walletAfter = await creditDriver(claimed, ride.driverId, f.driverEarning, 'online', f.fare, f.commission); paymentStatus = 'paid' }
    } else {
      // An installed rider app may have paid before the ride was ended.
      const s = await settleOnlinePayment(String(ride._id))
      if (s.state === 'paid') { paymentStatus = 'paid'; walletAfter = s.driverWalletBalance ?? walletAfter }
    }
  }

  const codSettled = await settleCod(String(ride._id))
  if (codSettled.balance != null) walletAfter = codSettled.balance

  return {
    status: 200,
    body: {
      success: true,
      fare: f.fare, commissionPercent,
      adminProfit: f.commission,
      driverEarning: f.driverEarning,
      driverWalletBalance: walletAfter ?? 0,
      codSettled: codSettled.amount,
      ...(codSettled.pending ? { codPendingRemittance: codSettled.pending } : {}),
      paymentMode: mode,
      paymentStatus,
      amountDue: f.amountDue,
      couponDiscount: f.coupon,
      awaitingPayment: paymentStatus !== 'paid',
      // The exact cash to take from the rider (cash rides, and a prepaid trip's
      // shortfall when the driver takes it in cash).
      ...(mode === 'cash' && !prepaid ? { cashToCollect: f.amountDue } : {}),
      ...(shortfall > 0 ? { prepaidShortfall: true, cashToCollect: shortfall } : {}),
      ...(switched ? { paymentSwitchedToCash: true } : {}),
      ...(riderWalletBalance != null ? { riderWalletBalance } : {}),
    },
  }
}

// Cash on delivery: the sender's money that travelled in the driver's pocket.
// Not revenue, never commissioned; stamped first so it can only move once.
//
// The sender is credited only what the driver's wallet can cover — down to the
// admin's maxNegativeWallet — never the whole rider-chosen COD regardless: a
// sender and a driver colluding on a ₹10,000 "COD" would otherwise mint wallet
// money backed by a driver balance that is never repaid. The rest is recorded
// as codPendingRemittance on the ride for an admin to collect and pay out.
// Every sender credit writes a WalletTransaction { source 'cod', ref 'cod:<rideId>' }.
async function maxNegativeWallet(): Promise<number> {
  try {
    const s: any = await Settings.findOne({ key: 'global' }).select('driverApp').lean()
    const v = Math.abs(Number(s?.driverApp?.maxNegativeWallet ?? 500))
    return Number.isFinite(v) ? v : 500
  } catch { return 500 }
}

async function settleCod(rideId: string): Promise<{ amount: number; balance?: number; pending?: number }> {
  const ride: any = await Ride.findOneAndUpdate(
    { _id: rideId, service: 'delivery', codCollected: { $gt: 0 }, codSettledAt: null },
    { $set: { codSettledAt: new Date() } }, { new: true },
  ).lean()
  if (!ride) return { amount: 0 }
  const cod = Math.max(0, Math.round(money(ride.codCollected)))
  let balance: number | undefined
  let credited = 0
  try {
    if (ride.driverId) {
      const maxNeg = await maxNegativeWallet()
      // Optimistic on the balance read, so the cap holds against a parallel
      // wallet movement on the same driver.
      for (let attempt = 0; attempt < 5; attempt++) {
        const d: any = await Driver.findById(ride.driverId).select('walletBalance').lean()
        if (!d) break
        const before = Number(d.walletBalance) || 0
        const take = Math.min(cod, Math.max(0, Math.floor(before + maxNeg)))
        if (take <= 0) { balance = before; break }
        const updated: any = await Driver.findOneAndUpdate(
          { _id: ride.driverId, walletBalance: d.walletBalance ?? null },
          { $inc: { walletBalance: -take } }, { new: true },
        ).select('walletBalance').lean()
        if (!updated) continue
        credited = take
        balance = updated.walletBalance
        await Transaction.create({
          driverId: ride.driverId, rideId: ride._id, type: 'cod_remittance',
          amount: -take, paymentMode: 'cash',
          description: `COD ₹${take} collected from receiver, owed to sender` + (take < cod ? ` (₹${cod - take} still to remit)` : ''),
          balanceAfter: balance,
        })
        break
      }
    }
    if (credited > 0 && ride.riderId) {
      const u: any = await User.findByIdAndUpdate(ride.riderId, { $inc: { walletBalance: credited } }, { new: true }).select('walletBalance').lean()
      if (u) {
        await WalletTransaction.create({
          userId: ride.riderId, type: 'credit', amount: credited, balanceAfter: u.walletBalance || 0,
          note: 'Cash on delivery collected for your parcel', source: 'cod', ref: `cod:${String(ride._id)}`,
        })
      }
    }
  } catch (e) {
    // Leave codSettledAt stamped: an unsettled balance is a reconciliation task,
    // a double payout is not recoverable.
    console.error('[complete] COD settlement failed', e)
  }
  const pending = Math.max(0, cod - credited)
  await Ride.updateOne({ _id: ride._id }, { $set: { codSenderCredited: credited, codPendingRemittance: pending } }).catch(() => {})
  if (pending > 0) console.warn('[complete] COD only partly remitted', { rideId: String(ride._id), cod, credited, pending })
  return { amount: credited, balance, pending }
}

/** Give a verified-but-unusable online payment back to the rider's wallet. */
async function releaseOnlinePayment(rideId: string, paymentId: string, amount: number, riderId: any, why: string): Promise<number> {
  const rel = await Ride.updateOne(
    { _id: rideId, 'onlinePayment.paymentId': paymentId, 'onlinePayment.settled': { $ne: true } },
    { $unset: { onlinePayment: 1 } },
  )
  if (!rel.modifiedCount) return 0
  return refundRidePayment(riderId, paymentId, amount, why)
}

/** Credit a ride payment back to the rider's wallet, once per payment id. */
export async function refundRidePayment(riderId: any, paymentId: string, amount: number, why: string): Promise<number> {
  if (!riderId || !(amount > 0)) return 0
  const token = `ridepay-refund:${paymentId}`
  const u: any = await User.findOneAndUpdate(
    { _id: riderId, walletRechargeRefs: { $ne: token } },
    { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: token } }, { new: true },
  ).select('walletBalance').lean()
  if (!u) return 0
  await WalletTransaction.create({
    userId: riderId, type: 'credit', amount, balanceAfter: u.walletBalance || 0,
    note: why, source: 'refund', ref: `refund:ridepay:${paymentId}`,
  })
  return amount
}

export type OnlineSettle = {
  state: 'none' | 'held' | 'paid' | 'already' | 'short' | 'refunded'
  amountDue?: number
  paid?: number
  refunded?: number
  driverWalletBalance?: number
}

/**
 * Settle a completed online ride from the verified payment attached to it.
 * Exactly once: the paymentStatus pending→paid flip is conditioned on this
 * payment, and only that flip credits the driver. A payment that cannot pay the
 * ride (short, ride already paid or turned to cash) goes back to the wallet.
 */
export async function settleOnlinePayment(rideId: string): Promise<OnlineSettle> {
  const ride: any = await Ride.findById(rideId).lean()
  const op = ride?.onlinePayment
  if (!ride || !op?.paymentId) return { state: 'none' }
  if (op.settled) return { state: 'already', paid: op.amount, amountDue: ride.amountDue }
  if (ride.status === 'cancelled') {
    const refunded = await releaseOnlinePayment(rideId, op.paymentId, op.amount, ride.riderId, 'Refund: online payment for a cancelled ride')
    return { state: 'refunded', refunded, paid: op.amount }
  }
  if (ride.status !== 'completed') return { state: 'held', paid: op.amount }
  if (ride.paymentStatus === 'paid' || ride.paymentMode !== 'online') {
    const refunded = await releaseOnlinePayment(rideId, op.paymentId, op.amount, ride.riderId, 'Refund: this ride was already paid')
    return { state: 'refunded', refunded, paid: op.amount }
  }
  const due = Number(ride.amountDue) || 0
  if ((Number(op.amount) || 0) < due - PAY_TOLERANCE) {
    const refunded = await releaseOnlinePayment(rideId, op.paymentId, op.amount, ride.riderId, `Refund: online payment ₹${op.amount} was less than the ₹${due} due`)
    return { state: 'short', refunded, paid: op.amount, amountDue: due }
  }
  const flipped: any = await Ride.findOneAndUpdate(
    { _id: rideId, status: 'completed', paymentMode: 'online', paymentStatus: 'pending', 'onlinePayment.paymentId': op.paymentId, 'onlinePayment.settled': { $ne: true } },
    { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), 'onlinePayment.settled': true } },
    { new: true },
  ).lean()
  if (!flipped) {
    const again = await settleOnlinePaymentStateAfterRace(rideId, op)
    return again
  }
  const earning = Number(flipped.pendingDriverEarning) || 0
  const commission = Number(flipped.pendingCommission) || 0
  const bal = await creditDriver(flipped, flipped.driverId, earning, 'online', Number(flipped.totalFare) || 0, commission)
  return { state: 'paid', paid: op.amount, amountDue: due, driverWalletBalance: bal }
}

async function settleOnlinePaymentStateAfterRace(rideId: string, op: any): Promise<OnlineSettle> {
  const r: any = await Ride.findById(rideId).lean()
  if (r?.onlinePayment?.paymentId === op.paymentId && r.onlinePayment.settled) return { state: 'already', paid: op.amount }
  if (r?.onlinePayment?.paymentId === op.paymentId) {
    const refunded = await releaseOnlinePayment(rideId, op.paymentId, op.amount, r.riderId, 'Refund: this ride was already paid')
    return { state: 'refunded', refunded, paid: op.amount }
  }
  return { state: 'none' }
}

/**
 * Driver took cash for a completed online ride the rider has not paid:
 * it becomes a cash ride, and the commission is debited like any cash ride.
 */
export async function collectCash(rideId: string, driverId: string): Promise<SettleResult> {
  const ride: any = await Ride.findById(rideId).lean()
  if (!ride) return { status: 404, body: { error: 'Ride not found' } }
  if (!ride.driverId || String(ride.driverId) !== driverId) return { status: 403, body: { error: 'Not a participant in this ride', code: 'NOT_PARTICIPANT' } }
  if (chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))) {
    if (ride.prepaidShortfall && ride.status === 'completed' && ride.paymentStatus !== 'paid') return collectShortfallCash(ride)
    return { status: 400, body: { error: 'This trip was paid at booking', code: 'prepaid' } }
  }
  if (ride.status !== 'completed') return { status: 400, body: { error: 'End the ride first', code: 'notCompleted' } }
  if (ride.paymentStatus === 'paid') return { status: 400, body: { error: 'This ride is already paid', code: 'alreadyPaid', paymentMode: ride.paymentMode } }
  if (ride.paymentMode !== 'online') return { status: 400, body: { error: 'Only an unpaid online ride can be paid in cash' } }

  const flipped: any = await Ride.findOneAndUpdate(
    { _id: rideId, driverId: ride.driverId, status: 'completed', paymentMode: 'online', paymentStatus: 'pending', 'onlinePayment.paymentId': { $exists: false } },
    { $set: { paymentMode: 'cash', paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), cashCollectedAt: new Date(), paymentSwitchedToCash: true } },
    { new: true },
  ).lean()
  if (!flipped) {
    const now: any = await Ride.findById(rideId).select('paymentStatus paymentMode onlinePayment').lean()
    if (now?.onlinePayment?.paymentId) return { status: 409, body: { error: 'The rider has just paid online', code: 'paidOnline' } }
    return { status: 400, body: { error: 'This ride is already paid', code: 'alreadyPaid', paymentMode: now?.paymentMode } }
  }
  const commission = Number(flipped.pendingCommission) || 0
  const earning = Number(flipped.pendingDriverEarning) || 0
  const due = Number(flipped.amountDue) || 0
  const f = { commission, coupon: Math.max(0, Number(flipped.pendingCoupon) || 0), driverEarning: earning, fare: Number(flipped.totalFare) || 0 }
  const bal = await settleCashOnDriver(flipped, flipped.driverId, f, Number(flipped.commissionPercent) || 0)
  if (f.coupon > 0) await Ride.updateOne({ _id: rideId }, { $set: { couponReimbursed: f.coupon } })
  return { status: 200, body: { success: true, paymentMode: 'cash', paymentStatus: 'paid', cashToCollect: due, commission, driverWalletBalance: bal ?? 0 } }
}

// A prepaid trip's shortfall taken in cash: the driver already holds exactly
// what they were not credited at completion, so only the status moves.
async function collectShortfallCash(ride: any): Promise<SettleResult> {
  const flipped: any = await Ride.findOneAndUpdate(
    { _id: ride._id, status: 'completed', prepaidShortfall: true, paymentStatus: 'pending', 'onlinePayment.paymentId': { $exists: false } },
    { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), cashCollectedAt: new Date() } },
    { new: true },
  ).lean()
  if (!flipped) {
    const now: any = await Ride.findById(ride._id).select('paymentStatus onlinePayment').lean()
    if (now?.onlinePayment?.paymentId) return { status: 409, body: { error: 'The rider has just paid online', code: 'paidOnline' } }
    return { status: 400, body: { error: 'This ride is already paid', code: 'alreadyPaid' } }
  }
  const due = Number(flipped.amountDue) || 0
  const d: any = await Driver.findById(flipped.driverId).select('walletBalance').lean()
  return { status: 200, body: { success: true, paymentMode: 'cash', paymentStatus: 'paid', cashToCollect: due, commission: 0, driverWalletBalance: d?.walletBalance ?? 0 } }
}

/**
 * The rider pays a COMPLETED, unpaid wallet ride from their Gora wallet
 * (/wallet/pay with a rideId). Only a completed ride: before that the amount is
 * not final (extensions, waiting, extras) — the driver's End settles a wallet
 * ride itself. The amount is the server's amountDue, debited once under the
 * claim key `ride:<id>` that /complete uses too; the driver is credited what
 * was left pending (a prepaid trip's shortfall). A debit that loses the race to
 * another settlement is refunded at once.
 */
export async function payRideFromWallet(rideId: string, userId: string, note = 'Ride payment'): Promise<SettleResult> {
  const ride: any = await Ride.findById(rideId).lean()
  if (!ride) return { status: 404, body: { error: 'Ride not found' } }
  if (String(ride.riderId || '') !== String(userId)) return { status: 403, body: { error: 'Not your ride', code: 'NOT_PARTICIPANT' } }
  const balanceOf = async () => ((await User.findById(userId).select('walletBalance').lean()) as any)?.walletBalance || 0

  const claimKey = `ride:${rideId}`
  const already =
    ride.paymentStatus === 'paid' ||
    (ride.riderWalletDebit || 0) > 0 ||
    !!(await WalletTransaction.exists({ userId, type: 'debit', source: 'ride', ref: rideId })) ||
    !!(await User.exists({ _id: userId, walletRechargeRefs: claimKey }))
  if (already) return { status: 200, body: { success: true, alreadyPaid: true, balance: await balanceOf() } }
  if (ride.status !== 'completed') {
    return { status: 409, body: { error: 'This ride can be paid once it has ended', code: 'notPayableYet', rideStatus: ride.status } }
  }
  if (ride.paymentMode !== 'wallet') return { status: 400, body: { error: 'This ride is not paid by wallet' } }
  const amt = ride.amountDue != null ? Math.max(0, Math.round(money(ride.amountDue))) : riderAmountDue(ride)
  if (amt <= 0) return { status: 200, body: { success: true, alreadyPaid: true, balance: await balanceOf() } }

  const updated: any = await User.findOneAndUpdate(
    { _id: userId, walletBalance: { $gte: amt }, walletRechargeRefs: { $ne: claimKey } },
    { $inc: { walletBalance: -amt }, $push: { walletRechargeRefs: claimKey } }, { new: true },
  ).select('walletBalance').lean()
  if (!updated) {
    const u: any = await User.findById(userId).select('walletBalance walletRechargeRefs').lean()
    if (!u) return { status: 404, body: { error: 'User not found' } }
    if ((u.walletRechargeRefs || []).includes(claimKey)) return { status: 200, body: { success: true, alreadyPaid: true, balance: u.walletBalance || 0 } }
    return { status: 402, body: { error: 'Insufficient wallet balance', balance: u.walletBalance || 0, amountDue: amt } }
  }
  const row: any = await WalletTransaction.create({
    userId, type: 'debit', amount: amt, balanceAfter: updated.walletBalance,
    note, source: 'ride', ref: rideId,
  })
  const flipped: any = await Ride.findOneAndUpdate(
    { _id: rideId, status: 'completed', paymentMode: 'wallet', paymentStatus: { $ne: 'paid' } },
    { $set: { paymentStatus: 'paid', awaitingPayment: false, paidAt: new Date(), riderWalletDebit: amt } },
    { new: true },
  ).lean()
  if (!flipped) {
    // Settled some other way in between: give this debit straight back.
    const back: any = await User.findByIdAndUpdate(userId, { $inc: { walletBalance: amt } }, { new: true }).select('walletBalance').lean()
    await WalletTransaction.updateOne({ _id: row._id }, { $set: { ref: `void:${rideId}` } })
    await WalletTransaction.create({
      userId, type: 'credit', amount: amt, balanceAfter: back?.walletBalance || 0,
      note: 'Refund: this ride was already paid', source: 'refund', ref: `refund:${rideId}:walletpay:${row._id}`,
    })
    return { status: 200, body: { success: true, alreadyPaid: true, balance: back?.walletBalance || 0 } }
  }
  // Only a prepaid trip's shortfall left a driver credit pending; any other
  // completed wallet ride already settled the driver at its End.
  if (flipped.prepaidShortfall && flipped.driverId) {
    const earning = money(flipped.pendingDriverEarning)
    if (earning > 0) await creditDriver(flipped, flipped.driverId, earning, 'wallet', money(flipped.totalFare), money(flipped.pendingCommission))
  }
  return { status: 200, body: { success: true, amount: amt, balance: updated.walletBalance } }
}
