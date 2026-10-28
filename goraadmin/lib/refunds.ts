// ─────────────────────────────────────────────────────────────────────────────
// Giving back money captured before a ride happened.
//
// One settlement path for every cancellation, whether the system closed the
// ride ("No driver found", lib/dispatch.ts) or the rider/admin cancelled it
// (/rides/:id/cancel). Before this nothing refunded anything: a rider who had
// prepaid an outstation trip and cancelled it lost the whole fare.
//
// What is refunded, to the payer's Gora wallet (User.walletBalance + a
// WalletTransaction credit, source 'refund' — the rider-wallet convention):
//
//   • prepaidAmount — the outstation fare paid at booking, as linked to the
//     ride by lib/prepay.ts (server-verified, never a client figure) — minus
//     the cancellationFee the cancel route charged (rider cancelling after a
//     driver accepted/arrived). Never negative. The fee portion is simply
//     RETAINED: nothing credits the driver for it yet (cancel-fee settlement
//     is a separate policy that does not exist yet).
//   • paid split-fare shares — back to each payer, but only when no driver was
//     ever assigned. split/pay credits an assigned driver immediately, so after
//     an accept the share is already the driver's and is not refunded here.
//
// Never refunded automatically (flagged in refundReview for an admin instead):
//   • 'prepay_unlinked'   — charged upfront but the payment could not be tied
//                           to the ride (old app build, gateway lookup failed),
//                           so the amount is not known from a trusted source.
//   • 'cancelled_mid_trip' — a prepaid ride cancelled while ongoing: part of
//                           the trip happened, so a full refund is not
//                           obviously right.
//
// Safety: cancelling sets refundPending in the SAME atomic update that flips
// the status, so a crash before the credit is retried by the next sweep
// (expireUnmatchedRides). A one-minute lease stops two runners working the same
// ride at once, and every credit carries ref `refund:<rideId>:<item>`; an
// existing row with that ref means it was paid, so retries never pay twice.
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'
import ServiceConfig from '@/models/ServiceConfig'
import { chargedAtBooking } from './prepay'

/** Lease on a ride's refund work, so two concurrent runners do not both pay. */
export const REFUND_LEASE_MS = 60_000

/**
 * Why a ride being cancelled now must be refunded by hand, if it must.
 * `ride` is the ride as read just before the cancel (its status is the status
 * it is being cancelled FROM).
 */
export function refundReviewFor(ride: any): string | null {
  const prepaidBooking = chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || ''))
  if (prepaidBooking && ride.prepaidUnlinked === true) return 'prepay_unlinked'
  if (ride.status === 'ongoing' && (Number(ride.prepaidAmount) || 0) > 0) return 'cancelled_mid_trip'
  return null
}

/**
 * Pays out whatever a cancelled ride owes back (see top of file). Idempotent
 * and retry-safe. Returns the total refunded for this ride so far.
 */
export async function settleCancelRefunds(rideId: any): Promise<number> {
  const now = new Date()
  const ride: any = await Ride.findOneAndUpdate(
    {
      _id: rideId, status: 'cancelled', refundPending: true,
      $or: [{ refundLeaseAt: null }, { refundLeaseAt: { $lt: new Date(now.getTime() - REFUND_LEASE_MS) } }],
    },
    { $set: { refundLeaseAt: now } },
    { new: true },
  ).lean()
  if (!ride) return 0

  const id = String(ride._id)
  const midTrip = ride.cancelledFromStatus === 'ongoing'
  const fee = Math.max(0, Number(ride.cancellationFee) || 0)
  const what = ride.service || 'ride'
  const items: { userId: any; amount: number; ref: string; note: string }[] = []

  const prepaid = Math.round((Number(ride.prepaidAmount) || 0) * 100) / 100
  const prepaidBack = Math.max(0, Math.round((prepaid - fee) * 100) / 100)
  if (!midTrip && prepaidBack > 0 && ride.riderId) {
    items.push({
      userId: ride.riderId, amount: prepaidBack, ref: `refund:${id}:prepaid`,
      note: ride.cancelledBy === 'system'
        ? `Refund: no driver found for your ${what} booking`
        : `Refund: cancelled ${what} booking` + (fee > 0 && prepaid > 0 ? ` (₹${Math.min(fee, prepaid)} cancellation fee kept)` : ''),
    })
  }

  if (!midTrip && !ride.driverId) {
    const splits: any[] = ride.splitRequests || []
    splits.forEach((sp: any, i: number) => {
      const share = Math.round(Number(sp.share) || 0)   // split/pay debits Math.round(share)
      if (sp.status === 'paid' && sp.paidBy && share > 0) {
        items.push({
          userId: sp.paidBy, amount: share, ref: `refund:${id}:split:${sp._id || i}`,
          note: ride.cancelledBy === 'system'
            ? 'Refund: split-fare share, no driver was found for that ride'
            : 'Refund: split-fare share, that ride was cancelled',
        })
      }
    })
  }

  let refunded = 0
  for (const it of items) {
    if (await WalletTransaction.exists({ ref: it.ref })) { refunded += it.amount; continue }
    const user: any = await User.findByIdAndUpdate(it.userId, { $inc: { walletBalance: it.amount } }, { new: true })
      .select('walletBalance').lean()
    if (!user) continue   // account gone: nothing to credit; the rest still are
    await WalletTransaction.create({
      userId: it.userId, type: 'credit', amount: it.amount, balanceAfter: user.walletBalance || 0,
      note: it.note, source: 'refund', ref: it.ref,
    })
    refunded += it.amount
  }

  await Ride.updateOne(
    { _id: ride._id },
    { $set: { refundPending: false, refundedAmount: refunded }, $unset: { refundLeaseAt: 1 } },
  )
  return refunded
}

export type CancelOutcome = {
  error?: string
  status?: number
  alreadyCancelled?: boolean
  ride?: any
  cancellationFee: number
  review: string | null
  refundedAmount: number
}

/**
 * The rider/admin/driver cancel, as used by POST /rides/:id/cancel.
 *
 * Atomic transition: the update only lands if the ride is still in the status
 * just read, so a double tap, two devices, or the system's own "No driver
 * found" close racing this request can cancel it only once — and the refund is
 * set up exactly once. If the status moved underneath (say a driver accepted),
 * it re-reads and decides again with the new state.
 *
 * The fee rule is unchanged from the route: only a rider cancelling after a
 * driver accepted/arrived pays the service's configured cancellationFee.
 */
export async function cancelRide(rideId: any, by: string, reason?: string): Promise<CancelOutcome> {
  let ride: any = null
  let cancellationFee = 0
  let review: string | null = null
  for (let attempt = 0; attempt < 3 && !ride; attempt++) {
    const current: any = await Ride.findById(rideId).lean()
    if (!current) return { error: 'Ride not found', status: 404, cancellationFee: 0, review: null, refundedAmount: 0 }
    if (current.status === 'completed') return { error: 'Ride already completed', status: 400, cancellationFee: 0, review: null, refundedAmount: 0 }
    if (current.status === 'cancelled') return { alreadyCancelled: true, cancellationFee: 0, review: null, refundedAmount: 0 }

    // Only charge the rider once a driver has actually committed to the trip.
    // Cancelling a still-pending request stays free.
    cancellationFee = 0
    if (by === 'rider' && ['accepted', 'arrived'].includes(current.status)) {
      const cfg: any = await ServiceConfig.findOne({ service: current.service }).lean().catch(() => null)
      cancellationFee = Math.max(0, Number(cfg?.cancellationFee) || 0)
    }

    // A ride whose upfront payment could not be verified, or one cancelled
    // mid-trip, is flagged for an admin instead of refunded automatically.
    review = refundReviewFor(current)

    ride = await Ride.findOneAndUpdate(
      { _id: rideId, status: current.status },
      {
        $set: {
          status: 'cancelled',
          cancelledBy: by,
          cancellationReason: reason || '',
          cancellationFee,
          awaitingPayment: false,
          cancelledFromStatus: current.status,
          refundPending: true,
          ...(review ? { refundReview: review } : {}),
        },
      },
      { new: true },
    ).lean()
  }
  if (!ride) {
    return { error: 'The ride changed while cancelling. Please try again.', status: 409, cancellationFee: 0, review: null, refundedAmount: 0 }
  }

  if (review) {
    console.warn('[cancel] prepaid ride needs a manual refund review', {
      rideId: String(ride._id), review, prepaidAmount: ride.prepaidAmount || 0, paymentMode: ride.paymentMode,
    })
  }

  // Refund now; a failure is retried by the sweep (refundPending stays set).
  let refundedAmount = 0
  try { refundedAmount = await settleCancelRefunds(ride._id) } catch (e) { console.error('[cancel] refund failed', e) }

  return { ride, cancellationFee, review, refundedAmount }
}
