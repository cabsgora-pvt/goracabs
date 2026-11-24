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
  refineCandidatesWithTraffic, MATRIX_REFINE, crowKm, ETA_CONFIG,
  type DriverCandidate,
} from './eta'
import { sendPushAsync, pushToUserAsync } from './push'
import { settleCancelRefunds } from './refunds'
import { holdOf, holdMessage } from './account-hold'
import Settings from '@/models/Settings'

export const DISPATCH = {
  /** How long one captain has to accept before the offer moves on. */
  OFFER_TTL_SEC: 20,
  /** How many captains to try before opening the ride to everyone. */
  MAX_ROUNDS: 4,
  /**
   * A ride due later than this (scheduledAt / departureAt / hireStartAt) is not
   * offered at booking and not listed in any feed; activateScheduledRides
   * starts its offer ladder this many minutes before it is due.
   */
  SCHEDULE_LEAD_MIN: 30,
}

// ── Due time ─────────────────────────────────────────────────────────────────
/** When a ride is due: the latest of createdAt and any scheduled start. */
export function rideDueAt(ride: any): Date {
  let t = ride?.createdAt ? new Date(ride.createdAt).getTime() : Date.now()
  for (const f of ['scheduledAt', 'departureAt', 'hireStartAt']) {
    const v = ride?.[f] ? new Date(ride[f]).getTime() : NaN
    if (Number.isFinite(v) && v > t) t = v
  }
  return new Date(t)
}

/** True when the ride is due soon enough to be offered / listed to drivers. */
export function rideIsOpenForDispatch(ride: any, now: Date = new Date()): boolean {
  return rideDueAt(ride).getTime() <= now.getTime() + DISPATCH.SCHEDULE_LEAD_MIN * 60_000
}

// ── Settings, cached ─────────────────────────────────────────────────────────
// The driver feed reads the global settings on every 4 s poll of every online
// driver. 30 s staleness for wallet-block thresholds is harmless.
let settingsCache: { at: number; value: any } | null = null
export const SETTINGS_CACHE_MS = 30_000
export async function cachedGlobalSettings(): Promise<any> {
  const now = Date.now()
  if (settingsCache && now - settingsCache.at < SETTINGS_CACHE_MS) return settingsCache.value
  const value: any = await Settings.findOne({ key: 'global' }).lean().catch(() => null)
  settingsCache = { at: now, value }
  return value
}

// ── Throttled sweeps for hot paths ───────────────────────────────────────────
// Every online driver's feed poll used to run the full sweep set. Now at most
// one sweep per SWEEP_EVERY_MS per process; POST /api/cron/dispatch runs the
// same set (unthrottled) for an external scheduler.
const SWEEP_EVERY_MS = 5_000
let lastSweepAt = 0
let sweepRunning: Promise<void> | null = null
export async function runDispatchSweepsThrottled(): Promise<void> {
  const now = Date.now()
  if (sweepRunning || now - lastSweepAt < SWEEP_EVERY_MS) return
  lastSweepAt = now
  sweepRunning = (async () => {
    try {
      await sweepExpiredOffers()
      await activateScheduledRides()
    } catch (e) { console.error('[dispatch] sweep failed', e) }
  })()
  try { await sweepRunning } finally { sweepRunning = null }
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

// ── Service / zone gate (one rule) ───────────────────────────────────────────
const OPT_IN: Record<string, { accepts: string; allow: string }> = {
  rental: { accepts: 'acceptsRental', allow: 'allowRental' },
  outstation: { accepts: 'acceptsOutstation', allow: 'allowOutstation' },
  hire_driver: { accepts: 'acceptsHireDriver', allow: 'allowHireDriver' },
  delivery: { accepts: 'acceptsDelivery', allow: 'allowDelivery' },
}

/**
 * Mongo filter (on top of availableDriverFilter) for drivers who may take this
 * ride: vehicle type, the admin's allow* gate, the driver's own accepts* opt-in
 * for non-taxi services, the ride's zone, and no cash rides on a negative
 * wallet. driverEligibleFor applies the same rule to one driver in memory.
 */
export function driverFilterFor(ride: any): Record<string, any> {
  const filter: Record<string, any> = { selectedVehicleTypeName: ride.vehicleType }
  const o = OPT_IN[ride.service]
  if (o) { filter[o.accepts] = true; filter[o.allow] = { $ne: false } }
  else filter.allowTaxi = { $ne: false }
  if (ride.zoneId) filter.zoneId = String(ride.zoneId)
  if (ride.paymentMode === 'cash') filter.walletBalance = { $gte: 0 }
  return filter
}

/**
 * Is there a female driver who could take this ride right now (available,
 * matching, not declined it, not busy, within dispatch range)? Mirrors
 * candidatesFor's female-first pool: when one exists, only female drivers may
 * take a ride whose rider asked for one; when none does, everyone may.
 */
export async function femalePoolExists(ride: any): Promise<boolean> {
  if (ride.pickupLat == null || ride.pickupLng == null) return false
  const drivers: any[] = await Driver.find(availableDriverFilter({ ...driverFilterFor(ride), gender: 'female' }))
    .select('currentLat currentLng').limit(50).lean()
  const rejected = new Set((ride.rejectedBy || []).map(String))
  const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }
  const near = drivers.filter(d => !rejected.has(String(d._id))
    && crowKm(pickup, { lat: d.currentLat, lng: d.currentLng }) <= ETA_CONFIG.MAX_PICKUP_RADIUS_KM)
  if (!near.length) return false
  const busy = await busyDriverIds(near.map(d => String(d._id)))
  return near.some(d => !busy.has(String(d._id)))
}

export type Ineligible = { status: number; code: string; error: string; [k: string]: any }

/**
 * ONE eligibility rule for a driver and a pending ride — used by both
 * POST /rides/{id}/accept and the driver pending feed. Returns null when the
 * driver may take the ride, else the reason (HTTP status + stable `code`).
 *
 * `ctx.settings` is the global settings doc (wallet block); `ctx.femalePool`
 * memoises femalePoolExists per ride within one request.
 */
export async function driverEligibleFor(
  driver: any,
  ride: any,
  ctx: { settings?: any; femalePool?: Map<string, boolean>; now?: Date } = {},
): Promise<Ineligible | null> {
  const now = ctx.now || new Date()
  const driverId = String(driver._id)
  if (driver.status !== 'approved') {
    return { status: 403, code: 'NOT_APPROVED', error: 'Your account is not approved yet' }
  }
  if (driver.faceVerificationRequired) {
    return { status: 403, code: 'FACE_VERIFICATION_REQUIRED', error: 'Face verification required before taking rides', faceVerificationRequired: true, accountHold: true }
  }
  const hold = holdOf(driver)
  if (hold.held) return { status: 403, code: 'ACCOUNT_HOLD', error: holdMessage(hold), accountHold: true }
  if (!driver.isOnline) return { status: 403, code: 'OFFLINE', error: 'Go online to accept rides' }

  const da = ctx.settings?.driverApp || {}
  const maxNeg = Math.abs(Number(da.maxNegativeWallet ?? 500))
  if (da.walletBlockEnabled !== false && (driver.walletBalance || 0) < -maxNeg) {
    return { status: 403, code: 'WALLET_BLOCKED', error: `Low wallet balance (₹${Math.round(driver.walletBalance || 0)}). Please recharge to accept rides.`, walletBlocked: true }
  }

  if (ride.vehicleType !== driver.selectedVehicleTypeName) {
    return { status: 403, code: 'VEHICLE_MISMATCH', error: 'This ride is for a different vehicle type' }
  }
  const o = OPT_IN[ride.service]
  if (o) {
    if (driver[o.allow] === false) return { status: 403, code: 'SERVICE_NOT_ALLOWED', error: 'You are not allowed to take this service' }
    if (driver[o.accepts] !== true) return { status: 403, code: 'SERVICE_NOT_ENABLED', error: 'Turn this service on in Preferences to take it' }
  } else if (driver.allowTaxi === false) {
    return { status: 403, code: 'SERVICE_NOT_ALLOWED', error: 'You are not allowed to take this service' }
  }
  if (ride.zoneId) {
    if (!driver.zoneId || String(driver.zoneId) !== String(ride.zoneId)) {
      return { status: 403, code: 'WRONG_ZONE', error: 'This ride is outside your zone' }
    }
  } else if (driver.zoneId) {
    // A zone-less request (pickup outside every zone) only reaches drivers
    // within dispatch range of it — never the whole country.
    const far = driver.currentLat == null || driver.currentLng == null || ride.pickupLat == null || ride.pickupLng == null
      || crowKm({ lat: driver.currentLat, lng: driver.currentLng }, { lat: ride.pickupLat, lng: ride.pickupLng }) > ETA_CONFIG.MAX_PICKUP_RADIUS_KM
    if (far) return { status: 403, code: 'OUT_OF_RANGE', error: 'This ride is too far from you' }
  }
  if ((driver.walletBalance || 0) < 0 && ride.paymentMode === 'cash') {
    return { status: 403, code: 'CASH_PAUSED', error: 'Your wallet is negative, so cash rides are paused. Recharge your wallet to take cash rides again.', cashPaused: true }
  }
  if ((ride.rejectedBy || []).map(String).includes(driverId)) {
    return { status: 409, code: 'REJECTED', error: 'You declined this ride' }
  }
  if (ride.offeredTo && String(ride.offeredTo) !== driverId
      && ride.offerExpiresAt && new Date(ride.offerExpiresAt).getTime() > now.getTime()) {
    return { status: 409, code: 'OFFERED_TO_OTHER', error: 'This ride is being offered to another captain' }
  }
  if (!rideIsOpenForDispatch(ride, now)) {
    return { status: 409, code: 'NOT_OPEN_YET', error: `This scheduled ride opens ${DISPATCH.SCHEDULE_LEAD_MIN} min before pickup` }
  }
  if (ride.preferFemaleDriver === true && driver.gender !== 'female') {
    const key = String(ride._id)
    let pool = ctx.femalePool?.get(key)
    if (pool === undefined) {
      pool = await femalePoolExists(ride).catch(() => false)
      ctx.femalePool?.set(key, pool)
    }
    if (pool) return { status: 403, code: 'FEMALE_DRIVER_REQUESTED', error: 'The rider asked for a female captain' }
  }
  return null
}

// ── Per-driver accept lease ──────────────────────────────────────────────────
// POST /accept takes this for the few hundred ms between its busy check and its
// claim, so one driver accepting two rides at once is serialised. A stuck lease
// expires on its own after ACCEPT_LEASE_MS.
const ACCEPT_LEASE_MS = 8_000
export async function acquireAcceptLease(driverId: string, waitMs = 4_000): Promise<Date | null> {
  const deadline = Date.now() + waitMs
  for (;;) {
    const now = new Date()
    const until = new Date(now.getTime() + ACCEPT_LEASE_MS)
    const got = await Driver.updateOne(
      { _id: driverId, $or: [{ acceptLeaseUntil: null }, { acceptLeaseUntil: { $lte: now } }] },
      { $set: { acceptLeaseUntil: until } },
    )
    if (got.modifiedCount) return until
    if (Date.now() >= deadline) return null
    await new Promise(r => setTimeout(r, 100))
  }
}
export async function releaseAcceptLease(driverId: string, lease: Date): Promise<void> {
  await Driver.updateOne({ _id: driverId, acceptLeaseUntil: lease }, { $set: { acceptLeaseUntil: null } }).catch(() => {})
}

/** Ranked, still-eligible candidates for a ride (nearest-by-ETA first). */
export async function candidatesFor(ride: any): Promise<DriverCandidate[]> {
  if (ride.pickupLat == null || ride.pickupLng == null) return []
  const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }

  // Same gate as driverEligibleFor (accept + the pending feed), so a ride is
  // never offered to a driver who could then not take it.
  const filter = driverFilterFor(ride)

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
  // Ride preferences (admin-defined: pet friendly, extra luggage …): drivers
  // who offer all of them first; everyone else when none does, as above.
  const prefs: string[] = Array.isArray(ride.preferences) ? ride.preferences.filter(Boolean) : []
  if (ride.preferFemaleDriver === true) {
    if (prefs.length) {
      const both = await rank({ ...filter, gender: 'female', ridePreferences: { $all: prefs } })
      if (both.length) return both
    }
    const withGender = await rank({ ...filter, gender: 'female' })
    if (withGender.length) return withGender
  }
  if (prefs.length) {
    const withPrefs = await rank({ ...filter, ridePreferences: { $all: prefs } })
    if (withPrefs.length) return withPrefs
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
  // A ride booked for later is not offered yet: activateScheduledRides starts
  // the ladder SCHEDULE_LEAD_MIN before it is due. (Offering tomorrow's trip at
  // booking burned the ladder and the ride then fell out of every feed.)
  if (!rideIsOpenForDispatch(ride)) return null

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

/**
 * Scheduled rides whose due time is now within SCHEDULE_LEAD_MIN: start their
 * offer ladder (once — claimed on dispatchActivatedAt). Run by the throttled
 * hot-path sweep and by POST /api/cron/dispatch.
 */
export async function activateScheduledRides(limit = 25): Promise<number> {
  const now = new Date()
  const horizon = new Date(now.getTime() + DISPATCH.SCHEDULE_LEAD_MIN * 60_000)
  const dueBy = (f: string) => ({ $or: [{ [f]: null }, { [f]: { $lte: horizon } }] })
  const rows: any[] = await Ride.find({
    status: 'pending',
    dispatchActivatedAt: null,
    offeredTo: null,
    offerRound: { $in: [0, null] },
    $or: [{ scheduledAt: { $ne: null } }, { departureAt: { $ne: null } }, { hireStartAt: { $ne: null } }],
    $and: [dueBy('scheduledAt'), dueBy('departureAt'), dueBy('hireStartAt')],
  }).select('_id').limit(limit).lean()
  let started = 0
  for (const r of rows) {
    try {
      const claimed = await Ride.findOneAndUpdate(
        { _id: r._id, status: 'pending', dispatchActivatedAt: null },
        { $set: { dispatchActivatedAt: now } },
        { new: true },
      ).select('_id').lean()
      if (!claimed) continue
      await offerNext(String(r._id))
      started++
    } catch { /* keep sweeping */ }
  }
  return started
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
