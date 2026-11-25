// ─────────────────────────────────────────────────────────────────────────────
// Applying a verified Razorpay payment — one implementation per purpose, shared
// by the app's own confirmation calls (payment/razorpay/verify, driver wallet
// recharge, subscription buy) and the Razorpay webhook. Every function claims
// the SAME key the original route did, in the same atomic update that moves the
// money, so a payment confirmed by the app AND by the webhook (in any order, or
// at the same time) is applied exactly once:
//
//   rider wallet top-up   User.walletRechargeRefs  <paymentId>
//   ride payment          User.walletRechargeRefs  ridepay:<paymentId>
//   driver wallet         Driver.walletRechargeRefs <paymentId>
//   driver subscription   Driver.walletRechargeRefs sub:<paymentId>
//   outstation prepay     User.walletRechargeRefs  prepay:<paymentId> (lib/prepay)
//
// Amounts always come from Razorpay's own record of the order, never a client.
// ─────────────────────────────────────────────────────────────────────────────
import mongoose from 'mongoose'
import User from '@/models/User'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import WalletTransaction from '@/models/WalletTransaction'
import Transaction from '@/models/Transaction'
import SubscriptionPlan from '@/models/SubscriptionPlan'
import DriverSubscription from '@/models/DriverSubscription'
import { settleOnlinePayment, refundRidePayment } from './settlement'
import { franchiseShareFor } from './commission'

export type Applied = { status: number; body: any }

/** Rider wallet top-up: credit `amount` once per payment id. */
export async function creditRiderTopUp(userId: string, paymentId: string, amount: number): Promise<Applied> {
  if (!(amount > 0)) return { status: 400, body: { error: 'Payment not completed yet' } }
  if (await WalletTransaction.exists({ ref: paymentId, source: 'recharge' })) {
    const u: any = await User.findById(userId).select('walletBalance').lean()
    return { status: 200, body: { success: true, alreadyCredited: true, balance: u?.walletBalance || 0 } }
  }
  const updated: any = await User.findOneAndUpdate(
    { _id: userId, walletRechargeRefs: { $ne: paymentId } },
    { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: paymentId } },
    { new: true },
  ).select('walletBalance').lean()
  if (!updated) {
    const u: any = await User.findById(userId).select('walletBalance').lean()
    if (!u) return { status: 404, body: { error: 'User not found' } }
    return { status: 200, body: { success: true, alreadyCredited: true, balance: u.walletBalance || 0 } }
  }
  await WalletTransaction.create({
    userId: updated._id, type: 'credit', amount, balanceAfter: updated.walletBalance,
    note: 'Money added via Razorpay', source: 'recharge', ref: paymentId,
  })
  return { status: 200, body: { success: true, amount, balance: updated.walletBalance || 0 } }
}

// Paying an online ride with a verified Razorpay payment.
//   - The payment id is claimed once on the rider ("ridepay:<id>"), so a replay,
//     a doubled request or the webhook arriving too does nothing more.
//   - It is attached to the ride only while the ride is an unpaid online ride;
//     a completed ride is then settled at once (driver credited exactly once by
//     lib/settlement settleOnlinePayment), an ongoing one when it completes.
//   - A payment that cannot pay the ride (less than amountDue, ride already
//     paid / switched to cash / cancelled) is credited to the rider's wallet.
// The caller has checked the order is ours for this rider and ride.
export async function payRideWithPayment(userId: string, rideId: string, orderId: string, paymentId: string, amount: number): Promise<Applied> {
  if (!mongoose.isValidObjectId(rideId)) return { status: 404, body: { error: 'Ride not found' } }
  if (!(amount > 0)) return { status: 400, body: { error: 'Payment not completed yet' } }
  const ride: any = await Ride.findById(rideId).select('riderId').lean()
  if (!ride) return { status: 404, body: { error: 'Ride not found' } }
  if (String(ride.riderId || '') !== userId) return { status: 403, body: { error: 'Not your ride', code: 'NOT_PARTICIPANT' } }

  const token = `ridepay:${paymentId}`
  const claimed = await User.updateOne({ _id: userId, walletRechargeRefs: { $ne: token } }, { $push: { walletRechargeRefs: token } })
  if (!claimed.modifiedCount) {
    const r: any = await Ride.findById(rideId).select('paymentStatus amountDue').lean()
    return { status: 200, body: { success: r?.paymentStatus === 'paid', alreadyProcessed: true, paymentStatus: r?.paymentStatus, amountDue: r?.amountDue } }
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
    return {
      status: 409,
      body: {
        success: false, error: `This ride is not awaiting an online payment. ₹${refunded} was added to your Gora wallet.`,
        code: 'notAwaitingPayment', refundedToWallet: refunded, paymentStatus: r?.paymentStatus, paymentMode: r?.paymentMode,
      },
    }
  }

  const s = await settleOnlinePayment(rideId)
  if (s.state === 'paid' || s.state === 'already') {
    return { status: 200, body: { success: true, paymentStatus: 'paid', amountPaid: amount, amountDue: s.amountDue ?? attached.amountDue } }
  }
  if (s.state === 'held') {
    return { status: 200, body: { success: true, paymentStatus: 'pending', pendingCompletion: true, amountPaid: amount, amountDue: attached.amountDue } }
  }
  if (s.state === 'short') {
    return {
      status: 402,
      body: {
        success: false, code: 'amountShort',
        error: `₹${amount} paid but ₹${s.amountDue} is due. The ₹${s.refunded || 0} was added to your Gora wallet; please pay again.`,
        paymentStatus: 'pending', amountPaid: amount, amountDue: s.amountDue, refundedToWallet: s.refunded || 0,
      },
    }
  }
  return {
    status: 409,
    body: {
      success: false, code: 'notAwaitingPayment',
      error: `This ride is no longer awaiting payment. ₹${s.refunded || 0} was added to your Gora wallet.`,
      refundedToWallet: s.refunded || 0,
    },
  }
}

/** Driver wallet recharge: credit `amount` once per payment id. */
export async function creditDriverRecharge(driverId: string, paymentId: string, amount: number): Promise<Applied> {
  if (!(amount > 0)) return { status: 400, body: { error: 'Payment not completed yet' } }
  const updated: any = await Driver.findOneAndUpdate(
    { _id: driverId, walletRechargeRefs: { $ne: paymentId } },
    { $inc: { walletBalance: amount }, $push: { walletRechargeRefs: paymentId } },
    { new: true },
  ).select('walletBalance').lean()
  if (!updated) {
    const d: any = await Driver.findById(driverId).select('walletBalance').lean()
    if (!d) return { status: 404, body: { error: 'Driver not found' } }
    return { status: 200, body: { success: true, alreadyCredited: true, amount, walletBalance: d.walletBalance || 0 } }
  }
  await Transaction.create({
    driverId, type: 'recharge', amount, paymentMode: 'online',
    description: `Wallet recharge via Razorpay (${paymentId})`,
    balanceAfter: updated.walletBalance,
  })
  return { status: 200, body: { success: true, amount, walletBalance: updated.walletBalance } }
}

const DAY = 24 * 60 * 60 * 1000
/** A second wallet purchase of the same plan this soon is a double tap. */
const WALLET_DEDUPE_MS = 30 * 1000

/**
 * Activate / extend a driver's pass. `paymentId` given → paid via Razorpay
 * (claim 'sub:<paymentId>', retried on a lost race since the key cannot apply
 * twice). No paymentId → paid from the driver's wallet (claim
 * 'subw:<plan>:<expiry it extends>', one attempt, $gte-guarded debit).
 * The pass is extended with an optimistic guard on subscriptionExpiresAt in the
 * same atomic update as the claim / debit.
 */
export async function applyDriverSubscription(driverId: string, plan: any, paymentId?: string): Promise<Applied> {
  const price = Math.max(0, Number(plan.price) || 0)
  const durationMs = (Number(plan.durationDays) || 0) * DAY
  const paidViaGateway = !!paymentId

  let updated: any = null
  let now = new Date(), expiresAt = now, claimKey = ''
  const attempts = paidViaGateway ? 5 : 1
  for (let attempt = 0; attempt < attempts && !updated; attempt++) {
    const d: any = await Driver.findById(driverId).select('subscriptionExpiresAt walletBalance walletRechargeRefs').lean()
    if (!d) return { status: 404, body: { error: 'Driver not found' } }
    now = new Date()
    const cur: Date | null = d.subscriptionExpiresAt ? new Date(d.subscriptionExpiresAt) : null
    const extending = !!cur && cur > now
    const base = extending && cur ? cur : now
    expiresAt = new Date(base.getTime() + durationMs)
    claimKey = paidViaGateway ? `sub:${paymentId}` : `subw:${plan._id}:${cur ? cur.getTime() : 0}`
    if ((d.walletRechargeRefs || []).includes(claimKey)) break

    const filter: any = { _id: driverId, subscriptionExpiresAt: d.subscriptionExpiresAt ?? null, walletRechargeRefs: { $ne: claimKey } }
    const set: any = {
      subscriptionActive: true,
      subscriptionPlanId: plan._id,
      subscriptionPlanName: plan.name,
      subscriptionExpiresAt: expiresAt,
      subscriptionCommissionPercent: Number(plan.commissionPercentWhileActive) || 0,
    }
    if (!extending) set.subscriptionStartedAt = now
    const update: any = { $set: set, $push: { walletRechargeRefs: claimKey } }
    if (!paidViaGateway) {
      if ((d.walletBalance || 0) < price) {
        return { status: 402, body: { error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: d.walletBalance || 0 } }
      }
      filter.walletBalance = { $gte: price }
      update.$inc = { walletBalance: -price }
      // A double tap that reads the expiry the first tap JUST set would build
      // a new claim key; this guard, in the same update, stops it.
      filter.$or = [
        { subscriptionWalletPlanId: { $ne: String(plan._id) } },
        { subscriptionWalletBoughtAt: null },
        { subscriptionWalletBoughtAt: { $lt: new Date(now.getTime() - WALLET_DEDUPE_MS) } },
      ]
      set.subscriptionWalletBoughtAt = now
      set.subscriptionWalletPlanId = String(plan._id)
    }
    updated = await Driver.findOneAndUpdate(filter, update, { new: true })
      .select('walletBalance zoneId subscriptionCommissionPercent').lean()
  }

  if (!updated) {
    const d: any = await Driver.findById(driverId).select('walletBalance walletRechargeRefs subscriptionExpiresAt subscriptionWalletBoughtAt subscriptionWalletPlanId').lean()
    const justBought = !paidViaGateway && d?.subscriptionWalletPlanId === String(plan._id) &&
      d?.subscriptionWalletBoughtAt && Date.now() - new Date(d.subscriptionWalletBoughtAt).getTime() < WALLET_DEDUPE_MS + 5000
    if ((d?.walletRechargeRefs || []).includes(claimKey) || justBought) {
      const last = await DriverSubscription.findOne({ driverId }).sort({ createdAt: -1 }).lean()
      return { status: 200, body: { success: true, alreadyApplied: true, subscription: last, walletBalance: d?.walletBalance || 0, expiresAt: d?.subscriptionExpiresAt, paidVia: paidViaGateway ? 'razorpay' : 'wallet' } }
    }
    if (!paidViaGateway && (d?.walletBalance || 0) < price) {
      return { status: 402, body: { error: 'Insufficient wallet balance. Please recharge to buy this plan.', walletBalance: d?.walletBalance || 0 } }
    }
    return { status: 409, body: { error: 'Busy, please try again' } }
  }

  await DriverSubscription.updateMany({ driverId, status: 'active' }, { $set: { status: 'expired' } })
  // Franchise mode: a subscribed driver pays no ride commission, so the zone
  // admin's share comes from the subscription price instead (lib/commission).
  let franchiseShare: any
  try { franchiseShare = await franchiseShareFor(updated.zoneId, price) } catch (e) { console.error('[subscription] franchise share failed', e) }
  const sub = await DriverSubscription.create({
    driverId, planId: plan._id, planName: plan.name, price,
    durationDays: plan.durationDays, commissionPercentWhileActive: updated.subscriptionCommissionPercent,
    startedAt: now, expiresAt, status: 'active',
    zoneId: updated.zoneId || null, paidVia: paidViaGateway ? 'razorpay' : 'wallet', franchiseShare,
  })
  if (!paidViaGateway) {
    await Transaction.create({
      driverId, type: 'subscription', amount: -price,
      description: `Subscription: ${plan.name} (${plan.durationDays} days)`,
      balanceAfter: updated.walletBalance,
    })
  }
  return { status: 200, body: { success: true, subscription: sub, walletBalance: updated.walletBalance, expiresAt, paidVia: paidViaGateway ? 'razorpay' : 'wallet' } }
}

/** Subscription paid via Razorpay, from the order's own notes (webhook path). */
export async function applySubscriptionFromOrder(o: any, paymentId: string): Promise<Applied> {
  const driverId = String(o?.notes?.driverId || '')
  const planId = String(o?.notes?.planId || '')
  if (!mongoose.isValidObjectId(driverId) || !mongoose.isValidObjectId(planId)) return { status: 400, body: { error: 'Order notes incomplete' } }
  const plan: any = await SubscriptionPlan.findById(planId).lean()
  if (!plan) return { status: 404, body: { error: 'Plan not found' } }
  if ((Number(o.amount_paid) || 0) < Math.round(Math.max(0, Number(plan.price) || 0) * 100)) {
    return { status: 400, body: { error: 'Payment amount does not cover this plan' } }
  }
  return applyDriverSubscription(driverId, plan, paymentId)
}
