// ─────────────────────────────────────────────────────────────────────────────
// Offer-based dispatch.
//
// Before this, a pending ride was listed to EVERY matching online driver and
// whoever tapped first won. That is a grab-pool, not a dispatch: no driver is
// ever actually asked, nobody is accountable for a request nobody takes, and
// acceptance rate is unmeasurable.
//
// Rapido's model — and now ours — offers the ride to the best-ranked captain
// for a short window, pushes them a notification, and escalates to the next
// candidate when the window lapses or they decline.
//
// Backward compatible on purpose: once the ladder is exhausted the ride returns
// to the open pool, which is exactly the old behaviour. Rides created before
// this shipped (offerRound 0, offeredTo null) are treated as open-pool too.
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import {
  availableDriverFilter, getEtaFactor, rankCandidates,
  refineCandidatesWithTraffic, MATRIX_REFINE,
  type DriverCandidate,
} from './eta'
import { sendPushAsync, pushToUserAsync } from './push'
import { settleCancelRefunds } from './refunds'

export const DISPATCH = {
  /** How long one captain has to accept before the offer moves on. */
  OFFER_TTL_SEC: 20,
  /** How many captains to try before opening the ride to everyone. */
  MAX_ROUNDS: 4,
}

// ── Busy drivers ─────────────────────────────────────────────────────────────
// ONE rule, used by every place that decides whether a driver may get a new
// request: candidatesFor (the offer ladder), the /rides/book preview, the
// driver pending feed and the /accept backstop.
//
// A driver is busy when they have a ride that is
//   • arrived or ongoing, or
//   • accepted AND due within BUSY.ACCEPTED_DUE_WITHIN_MIN (or already due).
// "Due" is the latest of createdAt, scheduledAt, departureAt and hireStartAt.
// So a driver who accepted tomorrow's outstation trip keeps getting other
// requests until shortly before it.
//
// This replaces rankCandidates' own "busy" handling for dispatch, which kept a
// driver finishing an ongoing trip nearby as a chained candidate. The
// fare-screen ETA (eta.ts etaByVehicleType) is unchanged.
export const BUSY = {
  ACCEPTED_DUE_WITHIN_MIN: 60,
}

/** Mongo filter for rides that make their driver busy right now. */
export function busyRideFilter(now: Date = new Date()): Record<string, any> {
  const horizon = new Date(now.getTime() + BUSY.ACCEPTED_DUE_WITHIN_MIN * 60_000)
  // max(a, b, c, d) <= horizon  ⇔  each of them is <= horizon (or missing).
  const dueBy = (f: string) => ({ $or: [{ [f]: null }, { [f]: { $lte: horizon } }] })
  return {
    $or: [
      { status: { $in: ['arrived', 'ongoing'] } },
      {
        status: 'accepted',
        createdAt: { $lte: horizon },
        $and: [dueBy('scheduledAt'), dueBy('departureAt'), dueBy('hireStartAt')],
      },
    ],
  }
}

/** Ids of the given drivers who are busy (see BUSY). */
export async function busyDriverIds(driverIds: string[], now: Date = new Date()): Promise<Set<string>> {
  if (!driverIds.length) return new Set()
  const rows: any[] = await Ride.find({ driverId: { $in: driverIds }, ...busyRideFilter(now) })
    .select('driverId').lean()
  return new Set(rows.map(r => String(r.driverId)))
}

/** Drops busy drivers from a candidate list. */
export function withoutBusyDrivers<T extends { _id?: any }>(drivers: T[], busy: Set<string>): T[] {
  return drivers.filter(d => !busy.has(String(d._id)))
}

/** True when this driver is busy, ignoring the ride `exceptRideId`. */
export async function driverIsBusy(driverId: string, exceptRideId?: string, now: Date = new Date()): Promise<boolean> {
  const q: Record<string, any> = { driverId, ...busyRideFilter(now) }
  if (exceptRideId) q._id = { $ne: exceptRideId }
  return !!(await Ride.exists(q))
}

/** Ranked, still-eligible candidates for a ride (nearest-by-ETA first). */
export async function candidatesFor(ride: any): Promise<DriverCandidate[]> {
  if (ride.pickupLat == null || ride.pickupLng == null) return []
  const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }

  const filter: Record<string, any> = { selectedVehicleTypeName: ride.vehicleType }
  if (ride.service === 'rental') { filter.acceptsRental = true; filter.allowRental = { $ne: false } }
  else if (ride.service === 'outstation') { filter.acceptsOutstation = true; filter.allowOutstation = { $ne: false } }
  else if (ride.service === 'hire_driver') { filter.acceptsHireDriver = true; filter.allowHireDriver = { $ne: false } }
  else if (ride.service === 'delivery') { filter.acceptsDelivery = true; filter.allowDelivery = { $ne: false } }
  else { filter.allowTaxi = { $ne: false }; if (ride.zoneId) filter.zoneId = String(ride.zoneId) }

  const rank = async (f: Record<string, any>): Promise<DriverCandidate[]> => {
    const [factor, drivers] = await Promise.all([
      getEtaFactor(pickup),
      Driver.find(availableDriverFilter(f))
        .select('selectedVehicleTypeName currentLat currentLng fcmToken')
        .lean() as Promise<any[]>,
    ])

    const rejected = new Set((ride.rejectedBy || []).map(String))
    const eligible = (drivers as any[]).filter(d => !rejected.has(String(d._id)))
    // Busy drivers (see BUSY) are removed outright rather than handed to
    // rankCandidates, which would keep one finishing a trip nearby as a chained
    // candidate.
    const busy = await busyDriverIds(eligible.map(d => String(d._id)))
    let ranked = rankCandidates(withoutBusyDrivers(eligible, busy), pickup, factor)

    // This is the ranking that decides who is actually offered the ride, so it is
    // where a traffic-aware estimate is worth paying for: one batched call per
    // offer round, against a shortlist. The geometric model cannot tell that the
    // "nearest" captain is on the wrong side of a level crossing.
    if (MATRIX_REFINE.DISPATCH) {
      ranked = await refineCandidatesWithTraffic(ranked, pickup)
    }

    // Carry the token through so offering does not need a second lookup.
    const byId = new Map<string, any>(eligible.map(d => [String(d._id), d]))
    return ranked.map(c => ({ ...c, fcmToken: byId.get(c.id)?.fcmToken } as any))
  }

  // Tries the female-only pool first. Falling back to everyone when nobody
  // matches means the preference is a best-effort match, never a reason the
  // ride sits unassigned — stranding a rider would be a worse safety outcome
  // than not finding a female driver in time.
  if (ride.preferFemaleDriver === true) {
    const withGender = await rank({ ...filter, gender: 'female' })
    if (withGender.length) return withGender
  }
  return rank(filter)
}

/**
 * Offers a pending ride to its next-best candidate and pushes them.
 * Returns the driver id offered to, or null when nobody is left (the ride then
 * sits in the open pool).
 */
export async function offerNext(rideId: string): Promise<string | null> {
  const ride: any = await Ride.findById(rideId)
  if (!ride || ride.status !== 'pending') return null

  if ((ride.offerRound || 0) >= DISPATCH.MAX_ROUNDS) {
    // Ladder exhausted — open the ride to everyone rather than stranding it.
    if (ride.offeredTo) {
      ride.offeredTo = null
      ride.offerExpiresAt = undefined
      await ride.save()
    }
    return null
  }

  const already = new Set<string>([
    ...(ride.rejectedBy || []).map(String),
    ...(ride.offeredTo ? [String(ride.offeredTo)] : []),
  ])
  const next = (await candidatesFor(ride)).find(c => !already.has(c.id))
  if (!next) {
    ride.offeredTo = null
    ride.offerExpiresAt = undefined
    ride.offerRound = DISPATCH.MAX_ROUNDS   // stop retrying; fall back to the pool
    await ride.save()
    return null
  }

  const now = new Date()
  ride.offeredTo = next.id as any
  ride.offeredAt = now
  ride.offerExpiresAt = new Date(now.getTime() + DISPATCH.OFFER_TTL_SEC * 1000)
  ride.offerRound = (ride.offerRound || 0) + 1
  ride.offerEtaMin = next.etaMin
  await ride.save()

  sendPushAsync((next as any).fcmToken, {
    title: 'New ride request',
    body: `${next.etaMin} min away · ${ride.pickupAddress || 'Pickup nearby'}`,
    channelId: 'ride_requests',
    data: {
      type: 'ride_offer',
      rideId: String(ride._id),
      service: String(ride.service || 'taxi'),
      etaMin: String(next.etaMin),
      expiresInSec: String(DISPATCH.OFFER_TTL_SEC),
    },
  })

  return next.id
}

/**
 * Moves on any offers whose window has lapsed. Called opportunistically from
 * the driver feed (so it self-heals without a scheduler) and by the cron route.
 */
export async function sweepExpiredOffers(limit = 25): Promise<number> {
  // Close rides nobody took before re-offering anything: an overdue ride must
  // not burn another rung of the ladder (and push another driver) first.
  await expireUnmatchedRides(limit).catch(() => 0)

  const now = new Date()
  const stale: any[] = await Ride.find({
    status: 'pending',
    offeredTo: { $ne: null },
    offerExpiresAt: { $lt: now },
  }).select('_id').limit(limit).lean()

  let moved = 0
  for (const r of stale) {
    try {
      // CLAIM the lapsed offer before re-offering it. Every online driver runs
      // this sweep on their 4s poll, so without an atomic claim two drivers can
      // both see the same lapsed ride and both call offerNext — offering it
      // twice and burning two rungs of the ladder for one timeout.
      //
      // findOneAndUpdate is atomic: exactly one caller flips offerExpiresAt, and
      // only that caller proceeds.
      const claimed = await Ride.findOneAndUpdate(
        { _id: r._id, status: 'pending', offerExpiresAt: { $lt: now } },
        { $set: { offerExpiresAt: new Date(now.getTime() + 5000) } },  // brief lease
        { new: true },
      ).select('_id').lean()
      if (!claimed) continue   // another poller got it

      if (await offerNext(String(r._id))) moved++
    } catch { /* keep sweeping the rest */ }
  }
  return moved
}

/** True when this driver may see this ride right now. */
export function driverMaySee(ride: any, driverId: string): boolean {
  // Open pool: never offered, or the ladder is done.
  if (!ride.offeredTo) return true
  if (ride.offerExpiresAt && new Date(ride.offerExpiresAt) < new Date()) return true
  return String(ride.offeredTo) === String(driverId)
}

// ── No driver found → the ride closes itself ─────────────────────────────────
// A pending ride used to stay pending forever: the driver feed stops listing it
// after 2 min (taxi) or 15 min (other services), and the rider watched
// "Looking for nearby drivers" until they gave up and cancelled by hand.
//
// Rule: an instant ride still pending NO_DRIVER.TIMEOUT_SEC after it became due
// is cancelled by the system. "Due" is the latest of createdAt and any
// scheduled start the ride carries (scheduledAt; outstation/rental departureAt;
// hire hireStartAt), so a ride booked for later is untouched until its time.
//
// Runs from (a) the rider's own poll of GET /rides/:id, (b) sweepExpiredOffers
// on every driver feed poll. Atomic: one findOneAndUpdate guarded by
// status 'pending' + the age condition, so exactly one caller wins, and an
// accept racing it either lands first (ride no longer pending → not closed) or
// finds the ride already cancelled (its own atomic claim on 'pending' fails).
export const NO_DRIVER = {
  TIMEOUT_SEC: 180,
  REASON: 'No driver found',
  MESSAGE: 'No drivers available right now. Please try again.',
}

/** Mongo filter: pending rides that have waited past the timeout. */
export function noDriverOverdueFilter(now: Date = new Date()): Record<string, any> {
  const cutoff = new Date(now.getTime() - NO_DRIVER.TIMEOUT_SEC * 1000)
  // `{ f: null }` matches both a missing field and an explicit null.
  const dueBy = (f: string) => ({ $or: [{ [f]: null }, { [f]: { $lte: cutoff } }] })
  return {
    status: 'pending',
    createdAt: { $lte: cutoff },
    // Charged upfront with no verified link to the payment: closing it would
    // strand the money, so it is left as before (see lib/prepay.ts).
    prepaidUnlinked: { $ne: true },
    $and: [dueBy('scheduledAt'), dueBy('departureAt'), dueBy('hireStartAt')],
  }
}

/**
 * Closes one ride as "No driver found" if, and only if, it is overdue.
 * Idempotent: returns true only for the single call that actually closed it.
 */
export async function expireIfNoDriver(rideId: any, now: Date = new Date()): Promise<boolean> {
  const ride: any = await Ride.findOneAndUpdate(
    { _id: rideId, ...noDriverOverdueFilter(now) },
    {
      $set: {
        status: 'cancelled',
        cancelledBy: 'system',
        cancellationReason: NO_DRIVER.REASON,
        cancellationFee: 0,
        awaitingPayment: false,
        offeredTo: null,
        cancelledFromStatus: 'pending',
        // Always set; settleCancelRefunds (lib/refunds.ts) clears it after
        // refunding whatever was captured (usually nothing). Written in the
        // same update as the cancel, so a crash between the two never loses one.
        refundPending: true,
      },
      $unset: { offerExpiresAt: 1 },
    },
    { new: true },
  ).select('_id riderId').lean()
  if (!ride) return false

  pushToUserAsync(ride.riderId, {
    title: 'No driver found',
    body: NO_DRIVER.MESSAGE,
    channelId: 'ride_updates',
    data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'system', reason: NO_DRIVER.REASON },
  })

  await settleCancelRefunds(ride._id).catch(e => console.error('[dispatch] no-driver refund failed', e))
  return true
}

/** Closes every overdue pending ride (bounded), and retries unfinished refunds. */
export async function expireUnmatchedRides(limit = 25): Promise<number> {
  const now = new Date()
  const overdue: any[] = await Ride.find(noDriverOverdueFilter(now)).select('_id').limit(limit).lean()
  let closed = 0
  for (const r of overdue) {
    try { if (await expireIfNoDriver(r._id, now)) closed++ } catch { /* keep sweeping */ }
  }

  // A refund interrupted by a crash or a DB hiccup — from this close or from a
  // rider/admin cancel — is picked up here.
  const unsettled: any[] = await Ride.find({ status: 'cancelled', refundPending: true })
    .select('_id').limit(10).lean()
  for (const r of unsettled) {
    try { await settleCancelRefunds(r._id) } catch { /* next sweep */ }
  }
  return closed
}
