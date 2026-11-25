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
import SupportTicket from '@/models/SupportTicket'
import {
  availableDriverFilter, getEtaFactor, rankCandidates,
  refineCandidatesWithTraffic, MATRIX_REFINE, crowKm, ETA_CONFIG,
  type DriverCandidate,
} from './eta'
import { sendPushAsync, pushToUserAsync } from './push'
import { settleCancelRefunds, REFUND_LEASE_MS } from './refunds'
import { releasePromoForRide } from './promo'
import { chargedAtBooking } from './prepay'
import { holdOf, holdMessage } from './account-hold'
import Settings from '@/models/Settings'

export const DISPATCH = {
  /** How long one captain has to accept before the offer moves on. */
  OFFER_TTL_SEC: 20,
  /** How many captains to try before opening the ride to everyone. */
  MAX_ROUNDS: 4,
  /**
   * The offer ladder of a ride booked for later starts this many minutes
   * before it is due (activateScheduledRides), for every service. A taxi /
   * delivery booked for later is also only LISTED to drivers from then.
   */
  SCHEDULE_LEAD_MIN: 30,
  /**
   * Outstation / rental / hire are planned trips: a driver must be able to see
   * and accept tomorrow's trip in advance (from booking, up to this far ahead),
   * not only 30 min before it — that hid every advance booking and then
   * auto-cancelled it at due + 3 min.
   */
  ADVANCE_SERVICES: ['outstation', 'rental', 'hire_driver'] as string[],
  ADVANCE_VISIBLE_HOURS: 48,
  /** Female-preference gate: female captains only, for at most this long / these rounds. */
  FEMALE_GATE_SEC: 60,
  FEMALE_FIRST_ROUNDS: 2,
}

export function isAdvanceService(service: any): boolean {
  return DISPATCH.ADVANCE_SERVICES.includes(String(service || ''))
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

/** Booked for later: due more than this after it was created. */
export const SCHEDULED_AFTER_MS = 10 * 60_000
export function isScheduledRide(ride: any): boolean {
  const created = ride?.createdAt ? new Date(ride.createdAt).getTime() : Date.now()
  return rideDueAt(ride).getTime() - created > SCHEDULED_AFTER_MS
}

/** How far ahead of its due time a ride may be listed to / accepted by drivers. */
export function visibilityLeadMs(ride: any): number {
  return isAdvanceService(ride?.service)
    ? DISPATCH.ADVANCE_VISIBLE_HOURS * 3_600_000
    : DISPATCH.SCHEDULE_LEAD_MIN * 60_000
}

/** True when the ride may be listed to / accepted by drivers now (see visibilityLeadMs). */
export function rideIsOpenForDispatch(ride: any, now: Date = new Date()): boolean {
  return rideDueAt(ride).getTime() <= now.getTime() + visibilityLeadMs(ride)
}

/** True when the ride's offer ladder may run (due within SCHEDULE_LEAD_MIN), any service. */
export function rideLadderOpen(ride: any, now: Date = new Date()): boolean {
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
/** Fire-and-forget variant for request handlers: never delays the response. */
export function kickDispatchSweeps(): void {
  runDispatchSweepsThrottled().catch(() => {})
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

// ── Female-driver preference ─────────────────────────────────────────────────
/**
 * While true, a rider's "female captain" preference is a hard gate (male
 * drivers may not take the ride if a female one could). It is a best-effort
 * match, never a reason the ride sits unassigned: the gate drops after
 * FEMALE_FIRST_ROUNDS offer rounds or FEMALE_GATE_SEC after the ladder started,
 * whichever comes first. (It used to last as long as any female captain was
 * online nearby — one who never answered stranded the ride.) A ride booked for
 * later keeps the gate until its ladder starts.
 */
export function femaleGateActive(ride: any, now: Date = new Date()): boolean {
  if (ride?.preferFemaleDriver !== true) return false
  if (!rideLadderOpen(ride, now)) return true
  if ((Number(ride.offerRound) || 0) >= DISPATCH.FEMALE_FIRST_ROUNDS) return false
  const created = ride.createdAt ? new Date(ride.createdAt).getTime() : now.getTime()
  const activated = ride.dispatchActivatedAt ? new Date(ride.dispatchActivatedAt).getTime() : 0
  const started = Math.max(created, activated)
  return now.getTime() - started < DISPATCH.FEMALE_GATE_SEC * 1000
}

/** Drivers who were offered this ride and let it lapse (not the live offer). */
function lapsedOfferees(ride: any, now: Date = new Date()): Set<string> {
  const live = ride.offeredTo && ride.offerExpiresAt && new Date(ride.offerExpiresAt).getTime() > now.getTime()
    ? String(ride.offeredTo) : ''
  return new Set((ride.offeredHistory || []).map(String).filter((id: string) => id !== live))
}

// Process-wide memo: every male driver's feed poll asked this for every
// female-preference ride.
export const FEMALE_POOL_CACHE_MS = 5_000
const femalePoolCache = new Map<string, { at: number; value: boolean }>()
export function _clearFemalePoolCache() { femalePoolCache.clear() }

/**
 * Is there a female driver who could take this ride right now (available,
 * matching, not declined it, not let its offer lapse, not busy, within
 * dispatch range)? Cached per ride for FEMALE_POOL_CACHE_MS.
 */
export async function femalePoolExists(ride: any): Promise<boolean> {
  if (ride.pickupLat == null || ride.pickupLng == null) return false
  const key = String(ride._id)
  const nowMs = Date.now()
  const hit = femalePoolCache.get(key)
  if (hit && nowMs - hit.at < FEMALE_POOL_CACHE_MS) return hit.value
  const value = await (async () => {
    const drivers: any[] = await Driver.find(availableDriverFilter({ ...driverFilterFor(ride), gender: 'female' }))
      .select('currentLat currentLng').limit(50).lean()
    const rejected = new Set((ride.rejectedBy || []).map(String))
    const lapsed = lapsedOfferees(ride)
    const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }
    const near = drivers.filter(d => !rejected.has(String(d._id)) && !lapsed.has(String(d._id))
      && crowKm(pickup, { lat: d.currentLat, lng: d.currentLng }) <= ETA_CONFIG.MAX_PICKUP_RADIUS_KM)
    if (!near.length) return false
    const busy = await busyDriverIds(near.map(d => String(d._id)))
    return near.some(d => !busy.has(String(d._id)))
  })()
  femalePoolCache.set(key, { at: nowMs, value })
  if (femalePoolCache.size > 2000) {
    for (const [k, v] of femalePoolCache) if (nowMs - v.at >= FEMALE_POOL_CACHE_MS) femalePoolCache.delete(k)
  }
  return value
}

export type Ineligible = { status: number; code: string; error: string; [k: string]: any }

/** The pickup-radius rule applies to rides due within this (not to advance bookings). */
export const RADIUS_DUE_WITHIN_MIN = 60

/**
 * ONE eligibility rule for a driver and a pending ride — used by both
 * POST /rides/{id}/accept, the driver pending feed and GET /rides/:id for a
 * pending ride. Returns null when the driver may take the ride, else the
 * reason (HTTP status + stable `code`).
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
  const hasFix = driver.currentLat != null && driver.currentLng != null && ride.pickupLat != null && ride.pickupLng != null
  const pickupKm = hasFix ? crowKm({ lat: driver.currentLat, lng: driver.currentLng }, { lat: ride.pickupLat, lng: ride.pickupLng }) : null
  if (ride.zoneId) {
    if (!driver.zoneId || String(driver.zoneId) !== String(ride.zoneId)) {
      return { status: 403, code: 'WRONG_ZONE', error: 'This ride is outside your zone' }
    }
    // A zone is a city: the far side of it is not "nearby" either. The same
    // pickup radius as zone-less rides, for rides due soon (an advance booking
    // is judged by zone only — where the driver is today says nothing about
    // tomorrow).
    const dueSoon = rideDueAt(ride).getTime() <= now.getTime() + RADIUS_DUE_WITHIN_MIN * 60_000
    if (dueSoon && pickupKm != null && pickupKm > ETA_CONFIG.MAX_PICKUP_RADIUS_KM) {
      return { status: 403, code: 'OUT_OF_RANGE', error: 'This ride is too far from you' }
    }
  } else if (driver.zoneId) {
    // A zone-less request (pickup outside every zone) only reaches drivers
    // within dispatch range of it — never the whole country.
    if (pickupKm == null || pickupKm > ETA_CONFIG.MAX_PICKUP_RADIUS_KM) return { status: 403, code: 'OUT_OF_RANGE', error: 'This ride is too far from you' }
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
    const lead = isAdvanceService(ride.service) ? `${DISPATCH.ADVANCE_VISIBLE_HOURS} h` : `${DISPATCH.SCHEDULE_LEAD_MIN} min`
    return { status: 409, code: 'NOT_OPEN_YET', error: `This scheduled ride opens ${lead} before pickup` }
  }
  if (ride.preferFemaleDriver === true && driver.gender !== 'female' && femaleGateActive(ride, now)) {
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

// ── Driver behaviour counters + reject cool-down ─────────────────────────────
// Rolling 24 h counters on the driver (dispatchStats), so acceptance / reject /
// cancel rates are visible to admins. A driver who rejects REJECT_COOLDOWN.COUNT
// requests within REJECT_COOLDOWN.WINDOW_MS is not OFFERED rides for
// REJECT_COOLDOWN.MS (the open-pool feed stays visible; they can still pick).
export const REJECT_COOLDOWN = { COUNT: 5, WINDOW_MS: 10 * 60_000, MS: 10 * 60_000 }
export const DRIVER_STATS_WINDOW_MS = 24 * 3_600_000
export type DriverEvent = 'offers' | 'accepts' | 'rejects' | 'cancels'

export async function recordDriverEvent(driverId: any, kind: DriverEvent): Promise<{ cooldownUntil?: Date }> {
  const now = new Date()
  const since = new Date(now.getTime() - DRIVER_STATS_WINDOW_MS)
  try {
    const inc = await Driver.updateOne({ _id: driverId, 'dispatchStats.windowStart': { $gte: since } }, { $inc: { [`dispatchStats.${kind}`]: 1 } })
    if (!inc.matchedCount) {
      const fresh = { windowStart: now, offers: 0, accepts: 0, rejects: 0, cancels: 0, [kind]: 1 }
      const reset = await Driver.updateOne(
        { _id: driverId, $or: [{ 'dispatchStats.windowStart': null }, { 'dispatchStats.windowStart': { $lt: since } }] },
        { $set: { dispatchStats: fresh } },
      )
      if (!reset.matchedCount) await Driver.updateOne({ _id: driverId }, { $inc: { [`dispatchStats.${kind}`]: 1 } })
    }
    if (kind !== 'rejects') return {}
    const d: any = await Driver.findOneAndUpdate(
      { _id: driverId },
      { $push: { recentRejectsAt: { $each: [now], $slice: -REJECT_COOLDOWN.COUNT } } },
      { new: true },
    ).select('recentRejectsAt offerCooldownUntil').lean()
    const list: Date[] = (d?.recentRejectsAt || []).map((t: any) => new Date(t))
    const cooling = d?.offerCooldownUntil && new Date(d.offerCooldownUntil).getTime() > now.getTime()
    if (!cooling && list.length >= REJECT_COOLDOWN.COUNT && now.getTime() - list[0].getTime() <= REJECT_COOLDOWN.WINDOW_MS) {
      const until = new Date(now.getTime() + REJECT_COOLDOWN.MS)
      await Driver.updateOne({ _id: driverId }, { $set: { offerCooldownUntil: until, recentRejectsAt: [] } })
      return { cooldownUntil: until }
    }
  } catch (e) { console.error('[dispatch] driver counter failed', e) }
  return {}
}

/** Ranked, still-eligible candidates for a ride (nearest-by-ETA first). */
export async function candidatesFor(ride: any): Promise<DriverCandidate[]> {
  if (ride.pickupLat == null || ride.pickupLng == null) return []
  const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }
  const now = new Date()

  // Same gate as driverEligibleFor (accept + the pending feed), so a ride is
  // never offered to a driver who could then not take it — plus the reject
  // cool-down, which only stops OFFERS.
  const filter = { ...driverFilterFor(ride), offerCooldownUntil: { $not: { $gt: now } } }

  const rank = async (f: Record<string, any>): Promise<DriverCandidate[]> => {
    const [factor, drivers] = await Promise.all([
      getEtaFactor(pickup),
      Driver.find(availableDriverFilter(f))
        .select('selectedVehicleTypeName currentLat currentLng fcmToken')
        .lean() as Promise<any[]>,
    ])

    const skip = new Set<string>([...(ride.rejectedBy || []).map(String), ...lapsedOfferees(ride, now)])
    const eligible = (drivers as any[]).filter(d => !skip.has(String(d._id)))
    // Busy drivers (see BUSY) are removed outright rather than handed to
    // rankCandidates, which would keep one finishing a trip nearby as a chained
    // candidate.
    const busy = await busyDriverIds(eligible.map(d => String(d._id)))
    let ranked = rankCandidates(withoutBusyDrivers(eligible, busy), pickup, factor)

    // This is the ranking that decides who is actually offered the ride, so it is
    // where a traffic-aware estimate is worth paying for: one batched call per
    // offer round, against a shortlist.
    if (MATRIX_REFINE.DISPATCH) {
      ranked = await refineCandidatesWithTraffic(ranked, pickup)
    }

    // Carry the token through so offering does not need a second lookup.
    const byId = new Map<string, any>(eligible.map(d => [String(d._id), d]))
    return ranked.map(c => ({ ...c, fcmToken: byId.get(c.id)?.fcmToken } as any))
  }

  // Female-only first, while the female gate lasts (femaleGateActive); then
  // everyone — the preference is a best-effort match, never a reason the ride
  // sits unassigned. Ride preferences (pet friendly, extra luggage …): drivers
  // who offer all of them first; everyone else when none does.
  const prefs: string[] = Array.isArray(ride.preferences) ? ride.preferences.filter(Boolean) : []
  if (femaleGateActive(ride, now)) {
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
 * sits in the open pool) or another caller moved the ride first.
 *
 * Atomic per rung: the write only lands if the ride is still pending, still
 * held by the same `offeredTo` and still on the same `offerRound` as read — so
 * a reject, the expiry sweep and the booking racing each other offer one rung
 * once and push one driver (it used to be read-modify-save; two callers could
 * both push and burn two rungs).
 */
export async function offerNext(rideId: string, expect?: { offeredTo: any }): Promise<string | null> {
  const ride: any = await Ride.findById(rideId).lean()
  if (!ride || ride.status !== 'pending') return null
  // A caller acting on a specific offer (a reject of it, the sweep of its
  // lapse) only moves THAT offer: if another caller already moved the ride on,
  // this one does nothing (it used to re-run the ladder on the new holder and
  // could close it).
  if (expect && String(ride.offeredTo || '') !== String(expect.offeredTo || '')) return null
  // The ladder of a ride booked for later starts SCHEDULE_LEAD_MIN before it is
  // due (activateScheduledRides); an advance booking sits in the open pool.
  if (!rideLadderOpen(ride)) return null

  const round = Number(ride.offerRound) || 0
  const guard: Record<string, any> = {
    _id: ride._id, status: 'pending',
    offeredTo: ride.offeredTo ?? null,
    offerRound: ride.offerRound == null ? { $in: [0, null] } : ride.offerRound,
  }

  if (round >= DISPATCH.MAX_ROUNDS) {
    // Ladder exhausted — open the ride to everyone rather than stranding it.
    if (ride.offeredTo) await Ride.updateOne(guard, { $set: { offeredTo: null }, $unset: { offerExpiresAt: 1 } })
    return null
  }

  const already = new Set<string>([
    ...(ride.rejectedBy || []).map(String),
    ...(ride.offeredHistory || []).map(String),
    ...(ride.offeredTo ? [String(ride.offeredTo)] : []),
  ])
  const next = (await candidatesFor(ride)).find(c => !already.has(c.id))
  if (!next) {
    await Ride.updateOne(guard, { $set: { offeredTo: null, offerRound: DISPATCH.MAX_ROUNDS }, $unset: { offerExpiresAt: 1 } })
    return null
  }

  const now = new Date()
  const claimed = await Ride.updateOne(guard, {
    $set: {
      offeredTo: next.id,
      offeredAt: now,
      offerExpiresAt: new Date(now.getTime() + DISPATCH.OFFER_TTL_SEC * 1000),
      offerRound: round + 1,
      offerEtaMin: next.etaMin,
    },
    $addToSet: { offeredHistory: next.id },
  })
  if (!claimed.modifiedCount) return null   // someone else moved this rung

  recordDriverEvent(next.id, 'offers').catch(() => {})
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
  }).select('_id offeredTo').limit(limit).lean()

  let moved = 0
  for (const r of stale) {
    try {
      // CLAIM the lapsed offer before re-offering it (a brief lease), so two
      // pollers do not both re-offer it; offerNext is itself atomic per rung.
      const claimed = await Ride.findOneAndUpdate(
        { _id: r._id, status: 'pending', offeredTo: r.offeredTo, offerExpiresAt: { $lt: now } },
        { $set: { offerExpiresAt: new Date(now.getTime() + 5000) } },
        { new: true },
      ).select('_id').lean()
      if (!claimed) continue   // another poller got it

      if (await offerNext(String(r._id), { offeredTo: r.offeredTo })) moved++
    } catch { /* keep sweeping the rest */ }
  }
  return moved
}

/**
 * Scheduled rides whose due time is now within SCHEDULE_LEAD_MIN: start their
 * offer ladder (once — claimed on dispatchActivatedAt). Run by the throttled
 * hot-path sweep and by POST /api/cron/dispatch. Advance bookings already in
 * the open pool get their ladder here too if nobody took them yet.
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
      await offerNext(String(r._id), { offeredTo: null })
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

// ── Review queue (admins) ────────────────────────────────────────────────────
/** Opens a support ticket so an admin sees a ride that needs a person. Best-effort. */
export async function openReviewTicket(ride: any, subject: string, text: string, priority: 'medium' | 'high' = 'high'): Promise<void> {
  try {
    await SupportTicket.create({
      userId: ride.riderId || undefined,
      role: 'user',
      userName: ride.riderName || 'Rider',
      subject: subject.slice(0, 200),
      category: 'ride_review',
      rideId: ride._id,
      priority,
      messages: [{ sender: 'system', message: text.slice(0, 1000) }],
    })
  } catch (e) { console.error('[dispatch] review ticket failed', e) }
}

// ── No driver found → the ride closes itself ─────────────────────────────────
// Rule: a pending ride still pending a grace after it became due is cancelled
// by the system ("No driver found"). "Due" is the latest of createdAt and any
// scheduled start (scheduledAt; outstation/rental departureAt; hire
// hireStartAt). The grace is NO_DRIVER.TIMEOUT_SEC, except for an outstation /
// rental / hire booked for later: NO_DRIVER.ADVANCE_GRACE_MIN — and such a
// booking that was PREPAID is not cancelled at all but flagged for an admin
// (needsReview, a support ticket, the rider told we are still arranging it).
//
// Runs from (a) the rider's own poll of GET /rides/:id, (b) the dispatch
// sweeps. Atomic: one findOneAndUpdate guarded by status 'pending' + the
// overdue condition, so exactly one caller wins against an accept.
export const NO_DRIVER = {
  TIMEOUT_SEC: 180,
  ADVANCE_GRACE_MIN: 30,
  REASON: 'No driver found',
  MESSAGE: 'No drivers available right now. Please try again.',
}
/** A prepaid ride whose payment is unlinked closes (for a manual refund) after this past due. */
export const PREPAID_UNLINKED_EXPIRE_MIN = 30

/** How long after it is due a pending ride waits before "No driver found". */
export function noDriverGraceMs(ride: any): number {
  return isAdvanceService(ride?.service) && isScheduledRide(ride)
    ? NO_DRIVER.ADVANCE_GRACE_MIN * 60_000
    : NO_DRIVER.TIMEOUT_SEC * 1000
}

// Mongo twins of rideDueAt / isScheduledRide / noDriverGraceMs, for $expr.
const DUE_EXPR = { $max: ['$createdAt', { $ifNull: ['$scheduledAt', '$createdAt'] }, { $ifNull: ['$departureAt', '$createdAt'] }, { $ifNull: ['$hireStartAt', '$createdAt'] }] }
const GRACE_EXPR = {
  $cond: [
    { $and: [{ $in: [{ $ifNull: ['$service', 'taxi'] }, DISPATCH.ADVANCE_SERVICES] }, { $gt: [{ $subtract: [DUE_EXPR, '$createdAt'] }, SCHEDULED_AFTER_MS] }] },
    NO_DRIVER.ADVANCE_GRACE_MIN * 60_000,
    NO_DRIVER.TIMEOUT_SEC * 1000,
  ],
}

/** Mongo filter: pending rides that have waited past their no-driver grace. */
export function noDriverOverdueFilter(now: Date = new Date()): Record<string, any> {
  const cutoff = new Date(now.getTime() - NO_DRIVER.TIMEOUT_SEC * 1000)
  return {
    status: 'pending',
    createdAt: { $lte: cutoff },
    // Charged upfront with no verified link to the payment: closed separately
    // (expirePrepaidUnlinked) with a manual refund review.
    prepaidUnlinked: { $ne: true },
    // Already flagged for an admin instead of closed.
    noDriverFlaggedAt: null,
    $expr: { $lte: [{ $add: [DUE_EXPR, GRACE_EXPR] }, now] },
  }
}

/** Give back a ride's coupon once (lib/promo releasePromoForRide claims couponReleasedAt). */
async function releaseRidePromo(rideId: any): Promise<void> {
  const ride: any = await Ride.findById(rideId).select('couponCode couponSource riderId couponReleasedAt').lean().catch(() => null)
  if (ride?.couponCode) await releasePromoForRide(ride)
}

/** A prepaid outstation/rental/hire booked for later is flagged, never auto-cancelled. */
function flagInsteadOfCancel(ride: any): boolean {
  if (!isAdvanceService(ride.service) || !isScheduledRide(ride)) return false
  return chargedAtBooking(String(ride.service || ''), String(ride.paymentMode || '')) && (Number(ride.prepaidAmount) || 0) > 0
}

/**
 * Closes one ride as "No driver found" if, and only if, it is overdue (or
 * flags a prepaid advance booking for review instead). Idempotent: returns
 * true only for the single call that actually closed it.
 */
export async function expireIfNoDriver(rideId: any, now: Date = new Date()): Promise<boolean> {
  const cur: any = await Ride.findOne({ _id: rideId, ...noDriverOverdueFilter(now) })
    .select('_id service paymentMode prepaidAmount createdAt scheduledAt departureAt hireStartAt riderId riderName').lean()
  if (!cur) return false

  if (flagInsteadOfCancel(cur)) {
    const flagged: any = await Ride.findOneAndUpdate(
      { _id: rideId, status: 'pending', noDriverFlaggedAt: null },
      { $set: { noDriverFlaggedAt: now, needsReview: true, needsReviewAt: now, reviewReason: 'no_driver_scheduled' } },
      { new: true },
    ).select('_id riderId riderName service prepaidAmount').lean()
    if (flagged) {
      await openReviewTicket(flagged, `Prepaid ${flagged.service} booking has no driver`,
        `No driver accepted this prepaid ${flagged.service} booking (₹${flagged.prepaidAmount || 0}) by ${NO_DRIVER.ADVANCE_GRACE_MIN} min after its start time. It was NOT cancelled. Arrange a driver, or cancel and refund it.`)
      pushToUserAsync(flagged.riderId, {
        title: 'Still arranging your driver',
        body: 'We have not found a driver yet. Our team is on it and will contact you shortly.',
        channelId: 'ride_updates',
        data: { type: 'ride_needs_review', rideId: String(flagged._id) },
      })
    }
    return false
  }

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
  await releaseRidePromo(ride._id)
  return true
}

/**
 * Pending rides charged upfront whose payment could not be linked
 * (prepaidUnlinked) used to stay pending forever. Past due + 30 min they are
 * cancelled with refundReview 'prepay_unlinked' (an admin refunds by hand) and
 * flagged needsReview.
 */
export async function expirePrepaidUnlinked(limit = 25, now: Date = new Date()): Promise<number> {
  const graceMs = PREPAID_UNLINKED_EXPIRE_MIN * 60_000
  const filter = {
    status: 'pending', prepaidUnlinked: true,
    createdAt: { $lte: new Date(now.getTime() - graceMs) },
    $expr: { $lte: [{ $add: [DUE_EXPR, graceMs] }, now] },
  }
  const rows: any[] = await Ride.find(filter).select('_id').limit(limit).lean()
  let closed = 0
  for (const r of rows) {
    try {
      const ride: any = await Ride.findOneAndUpdate(
        { _id: r._id, ...filter },
        {
          $set: {
            status: 'cancelled', cancelledBy: 'system', cancellationReason: NO_DRIVER.REASON, cancellationFee: 0,
            awaitingPayment: false, offeredTo: null, cancelledFromStatus: 'pending',
            refundPending: true, refundReview: 'prepay_unlinked',
            needsReview: true, needsReviewAt: now, reviewReason: 'prepay_unlinked_no_driver',
          },
          $unset: { offerExpiresAt: 1 },
        },
        { new: true },
      ).select('_id riderId riderName service').lean()
      if (!ride) continue
      closed++
      pushToUserAsync(ride.riderId, {
        title: 'No driver found',
        body: 'No driver was available. Our team will refund your payment shortly.',
        channelId: 'ride_updates',
        data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'system', reason: NO_DRIVER.REASON },
      })
      await openReviewTicket(ride, 'Refund needed: unlinked prepayment, no driver',
        'This booking was charged upfront but the payment could not be linked to it, and no driver took it. It was cancelled; refund the rider manually.')
      await settleCancelRefunds(ride._id).catch(() => 0)
      await releaseRidePromo(ride._id)
    } catch { /* keep sweeping */ }
  }
  return closed
}

/** Backoff before the next refund retry of a ride (attempt n ≥ 1). */
export function refundBackoffMs(attempt: number): number {
  return Math.min(60, 2 ** Math.max(0, attempt - 1)) * 60_000
}
export const REFUND_REVIEW_AFTER_ATTEMPTS = 8

/**
 * Retries unfinished cancel refunds, fairly: only rides whose lease has lapsed
 * and whose backoff has passed, oldest lease first (never-tried first), with a
 * per-ride attempt counter. It used to take the first 10 refundPending rides
 * every time, so 10 permanently failing rides starved every other refund.
 */
export async function retryUnsettledRefunds(limit = 10, now: Date = new Date()): Promise<number> {
  const leaseCutoff = new Date(now.getTime() - REFUND_LEASE_MS)
  const rows: any[] = await Ride.find({
    status: 'cancelled', refundPending: true,
    $and: [
      { $or: [{ refundLeaseAt: null }, { refundLeaseAt: { $lt: leaseCutoff } }] },
      { $or: [{ refundNextAt: null }, { refundNextAt: { $lte: now } }] },
    ],
  }).sort({ refundLeaseAt: 1, _id: 1 }).select('_id refundAttempts riderId riderName').limit(limit).lean()
  let done = 0
  for (const r of rows) {
    const attempt = (Number(r.refundAttempts) || 0) + 1
    await Ride.updateOne({ _id: r._id }, { $inc: { refundAttempts: 1 }, $set: { refundNextAt: new Date(now.getTime() + refundBackoffMs(attempt)) } }).catch(() => {})
    try { await settleCancelRefunds(r._id); done++ } catch { /* next sweep, after the backoff */ }
    if (attempt >= REFUND_REVIEW_AFTER_ATTEMPTS) {
      const f = await Ride.updateOne({ _id: r._id, refundPending: true, needsReview: { $ne: true } },
        { $set: { needsReview: true, needsReviewAt: now, reviewReason: 'refund_stuck' } }).catch(() => null)
      if (f?.modifiedCount) await openReviewTicket(r, 'Refund keeps failing', `The cancel refund for this ride failed ${attempt} times.`)
    }
  }
  return done
}

/** Closes every overdue pending ride (bounded), and retries unfinished refunds. */
export async function expireUnmatchedRides(limit = 25): Promise<number> {
  const now = new Date()
  const overdue: any[] = await Ride.find(noDriverOverdueFilter(now)).select('_id').limit(limit).lean()
  let closed = 0
  for (const r of overdue) {
    try { if (await expireIfNoDriver(r._id, now)) closed++ } catch { /* keep sweeping */ }
  }
  closed += await expirePrepaidUnlinked(limit, now).catch(() => 0)
  // A refund interrupted by a crash or a DB hiccup — from this close or from a
  // rider/admin cancel — is picked up here.
  await retryUnsettledRefunds(10, now).catch(() => 0)
  return closed
}

// ── Stuck active rides ───────────────────────────────────────────────────────
// An accepted / arrived / ongoing ride whose driver went silent, or that ran
// hours past its plan, used to sit "live" forever (and kept its rider from
// booking). The sweep flags it for an admin; it never ends or cancels it.
export const STUCK = {
  NO_LOCATION_MIN: 20,
  OVERDUE_HOURS: 3,
  /** A ride an admin resolved is not flagged again for this long. */
  RESOLVED_QUIET_MS: 60 * 60_000,
}
export const ACTIVE_RIDE_STATUSES = ['accepted', 'arrived', 'ongoing']

/** When the ride should reasonably have ended. */
export function expectedEndAt(ride: any): Date {
  const due = rideDueAt(ride).getTime()
  const startRaw = ride.startedAt || ride.rentalStartedAt || ride.hireStartedAt
  const start = startRaw ? new Date(startRaw).getTime() : due
  let planMin = Number(ride.duration) || 0
  if (ride.service === 'rental') planMin = (Number(ride.packageHours) || 0) * 60
  else if (ride.service === 'hire_driver') planMin = (Number(ride.hireTotalHours) || 0) * 60
  else if (ride.service === 'outstation' && ride.returnAt) {
    planMin = Math.max(planMin, (new Date(ride.returnAt).getTime() - start) / 60_000 + (Number(ride.duration) || 0))
  }
  return new Date(Math.max(start, due) + Math.max(30, planMin || 60) * 60_000)
}

/** Flags stuck active rides needsReview (+ stuckSince, reviewReason, a ticket). */
export async function sweepStuckRides(limit = 300, now: Date = new Date()): Promise<number> {
  const rows: any[] = await Ride.find({
    status: { $in: ACTIVE_RIDE_STATUSES },
    needsReview: { $ne: true },
    $or: [{ reviewResolvedAt: null }, { reviewResolvedAt: { $lt: new Date(now.getTime() - STUCK.RESOLVED_QUIET_MS) } }],
  }).select('status service driverId riderId riderName createdAt scheduledAt departureAt hireStartAt returnAt acceptedAt arrivedAt startedAt rentalStartedAt hireStartedAt duration packageHours hireTotalHours')
    .limit(limit).lean()
  if (!rows.length) return 0
  const driverIds = Array.from(new Set(rows.map(r => r.driverId).filter(Boolean).map(String)))
  const drivers: any[] = driverIds.length ? await Driver.find({ _id: { $in: driverIds } }).select('locationUpdatedAt').lean() : []
  const seen = new Map<string, number>(drivers.map(d => [String(d._id), d.locationUpdatedAt ? new Date(d.locationUpdatedAt).getTime() : 0]))
  let flagged = 0
  for (const r of rows) {
    const due = rideDueAt(r).getTime()
    // An accepted advance booking (tomorrow's trip) is not live yet.
    if (r.status === 'accepted' && due > now.getTime()) continue
    const ts = (v: any) => (v ? new Date(v).getTime() : 0)
    const lastSeen = Math.max(seen.get(String(r.driverId)) || 0, ts(r.acceptedAt), ts(r.arrivedAt), ts(r.startedAt), due)
    const silent = now.getTime() - lastSeen > STUCK.NO_LOCATION_MIN * 60_000
    const end = expectedEndAt(r).getTime()
    const overdue = now.getTime() > end + STUCK.OVERDUE_HOURS * 3_600_000
    if (!silent && !overdue) continue
    const reason = silent ? 'stuck_no_location' : 'stuck_overdue'
    const res = await Ride.updateOne(
      { _id: r._id, status: r.status, needsReview: { $ne: true } },
      { $set: { needsReview: true, needsReviewAt: now, reviewReason: reason, stuckSince: new Date(silent ? lastSeen : end) } },
    ).catch(() => null)
    if (!res?.modifiedCount) continue
    flagged++
    await openReviewTicket(r, silent ? 'Active ride: driver not reporting location' : 'Active ride running far past its plan',
      silent
        ? `Ride ${r.status}; no driver location for over ${STUCK.NO_LOCATION_MIN} min. Contact the driver/rider, then resolve, end or cancel it.`
        : `Ride ${r.status}; more than ${STUCK.OVERDUE_HOURS} h past its expected end. Check it, then resolve, end or cancel it.`)
  }
  return flagged
}

/**
 * Counts a driver's cancel once on their dispatchStats, and flags a mid-trip
 * driver cancel (cancelledFromStatus 'ongoing') needsReview. The cancel route
 * may call this right after cancelling; the cron sweep is the backstop.
 */
export async function noteDriverCancel(rideId: any, now: Date = new Date()): Promise<boolean> {
  const r: any = await Ride.findOneAndUpdate(
    { _id: rideId, status: 'cancelled', cancelledBy: 'driver', driverCancelNoted: { $ne: true } },
    { $set: { driverCancelNoted: true } },
    { new: true },
  ).select('_id driverId riderId riderName cancelledFromStatus cancellationReason needsReview').lean()
  if (!r) return false
  if (r.driverId) await recordDriverEvent(r.driverId, 'cancels')
  if (r.cancelledFromStatus === 'ongoing' && r.needsReview !== true) {
    await Ride.updateOne({ _id: r._id }, { $set: { needsReview: true, needsReviewAt: now, reviewReason: 'driver_cancelled_mid_trip' } })
    await openReviewTicket(r, 'Driver cancelled a trip in progress', `Reason given: ${r.cancellationReason || '(none)'}`)
  }
  return true
}

export async function sweepDriverCancels(limit = 50, now: Date = new Date()): Promise<number> {
  const rows: any[] = await Ride.find({
    status: 'cancelled', cancelledBy: 'driver', driverCancelNoted: { $ne: true },
    updatedAt: { $gte: new Date(now.getTime() - 24 * 3_600_000) },
  }).select('_id').limit(limit).lean()
  let n = 0
  for (const r of rows) { try { if (await noteDriverCancel(r._id, now)) n++ } catch { /* next */ } }
  return n
}
