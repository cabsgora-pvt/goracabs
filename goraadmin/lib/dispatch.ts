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
  availableDriverFilter, driverBusyRides, getEtaFactor, rankCandidates,
  refineCandidatesWithTraffic, MATRIX_REFINE,
  type DriverCandidate,
} from './eta'
import { sendPushAsync } from './push'

export const DISPATCH = {
  /** How long one captain has to accept before the offer moves on. */
  OFFER_TTL_SEC: 20,
  /** How many captains to try before opening the ride to everyone. */
  MAX_ROUNDS: 4,
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
    const busy = await driverBusyRides(eligible.map(d => String(d._id)))
    let ranked = rankCandidates(eligible, pickup, factor, busy)

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
