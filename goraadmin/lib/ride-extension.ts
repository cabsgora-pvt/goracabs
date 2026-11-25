// ─────────────────────────────────────────────────────────────────────────────
// Rental / hire extensions — priced on the server, confirmed by the rider.
//
// Before: the driver's 'extend' just added hours to the package for free (a
// rental's included km even grew with it), so extending turned paid
// extra-hours into nothing.
//
// Now:
//   driver  { action: 'extend', extraHours }  → ride.pendingExtension
//           { kind, hours, amount, requestedAt, expiresAt } — nothing billed yet
//   rider   { action: 'confirm_extend', requestedAt, amount } → applied atomically: hours added,
//           `fare` += amount, entry appended to ride.extensions
//   rider   { action: 'decline_extend' }      → pendingExtension cleared
// A pending request expires after EXTENSION_TTL_MS. One pending at a time (no
// replacing it), at most MAX_EXTENSION_REQUESTS per ride, and the rider's
// confirm must name the request they saw ({ requestedAt, amount }).
// ─────────────────────────────────────────────────────────────────────────────
import Ride from '@/models/Ride'
import Zone from '@/models/Zone'
import { quoteRental, RENTAL_LIMITS } from './rental-pricing'

export const MAX_EXTEND_HOURS = 12
export const EXTENSION_TTL_MS = 15 * 60 * 1000

/** Whole hours 1..MAX_EXTEND_HOURS, or null. */
export function parseExtraHours(v: any): number | null {
  const n = Number(v)
  if (!Number.isInteger(n) || n < 1 || n > MAX_EXTEND_HOURS) return null
  return n
}

/** Price of adding `extra` hours to a rental, plus the included km it adds. */
export async function priceRentalExtension(ride: any, extra: number): Promise<{ amount: number; addKm: number; basis: string }> {
  const oldHours = Number(ride.packageHours) || 0
  const newHours = oldHours + extra
  // Included km scale off the ORIGINAL per-hour allowance.
  const perHrKm = oldHours > 0 ? (Number(ride.packageKm) || 0) / oldHours : 0
  if (ride.zoneId && newHours <= RENTAL_LIMITS.MAX_HOURS && oldHours >= RENTAL_LIMITS.MIN_HOURS) {
    const zone: any = await Zone.findById(ride.zoneId).select('rentalPackages').lean().catch(() => null)
    const qOld = zone ? quoteRental({ zone, vehicleType: ride.vehicleType, hours: oldHours }) : null
    const qNew = zone ? quoteRental({ zone, vehicleType: ride.vehicleType, hours: newHours }) : null
    if (qOld && qNew && qNew.hours === newHours && qOld.hours === oldHours && qNew.fare > qOld.fare) {
      return { amount: Math.round(qNew.fare - qOld.fare), addKm: Math.max(0, qNew.km - qOld.km), basis: 'package' }
    }
  }
  const rate = Number(ride.extraHourRate) || 0
  return { amount: Math.round(rate * extra), addKm: Math.round(perHrKm * newHours) - (Number(ride.packageKm) || 0), basis: 'extra_hour_rate' }
}

/** Price of adding `extra` hours to a driver hire. */
export function priceHireExtension(ride: any, extra: number): { amount: number; basis: string } {
  let rate = Number(ride.hirePerHour) || 0
  let basis = 'hire_per_hour'
  if (rate <= 0 && (Number(ride.hireTotalHours) || 0) > 0) {
    rate = (Number(ride.fare) || 0) / Number(ride.hireTotalHours)
    basis = 'fare_per_booked_hour'
  }
  return { amount: Math.round(rate * extra), basis }
}

/** At most this many extension requests per ride (confirmed, declined or lapsed). */
export const MAX_EXTENSION_REQUESTS = 3

export type ExtensionRequestResult =
  | { ok: true; pendingExtension: any }
  | { ok: false; status: number; code: 'EXTENSION_PENDING' | 'EXTENSION_LIMIT' | 'NOT_ONGOING'; error: string; pendingExtension?: any }

/**
 * Stores a driver's extension request for the rider to confirm. One at a time:
 * a live request cannot be replaced (it used to be — the driver could swap the
 * price under the rider's confirm tap) until it lapses or the rider declines;
 * and at most MAX_EXTENSION_REQUESTS per ride. Atomic on both rules.
 */
export async function requestExtension(ride: any, kind: 'rental' | 'hire', hours: number, amount: number, addKm = 0): Promise<ExtensionRequestResult> {
  const now = new Date()
  const pendingExtension = { kind, hours, amount, addKm, requestedAt: now, expiresAt: new Date(now.getTime() + EXTENSION_TTL_MS) }
  const res = await Ride.updateOne(
    {
      _id: ride._id, status: 'ongoing',
      $or: [{ pendingExtension: null }, { 'pendingExtension.hours': null }, { 'pendingExtension.expiresAt': { $lt: now } }],
      extensionRequests: { $not: { $gte: MAX_EXTENSION_REQUESTS } },
    },
    { $set: { pendingExtension }, $inc: { extensionRequests: 1 } },
  )
  if (res.modifiedCount) return { ok: true, pendingExtension }
  const cur: any = await Ride.findById(ride._id).select('status pendingExtension extensionRequests').lean()
  const live = livePendingExtension(cur)
  if (cur?.status !== 'ongoing') return { ok: false, status: 409, code: 'NOT_ONGOING', error: 'The trip is not in progress' }
  if (live) return { ok: false, status: 409, code: 'EXTENSION_PENDING', error: 'An extension is already waiting for the rider. Wait for their answer.', pendingExtension: live }
  return { ok: false, status: 409, code: 'EXTENSION_LIMIT', error: `At most ${MAX_EXTENSION_REQUESTS} extension requests per trip` }
}

export function livePendingExtension(ride: any): any | null {
  const p = ride?.pendingExtension
  if (!p || !p.hours) return null
  if (p.expiresAt && new Date(p.expiresAt).getTime() < Date.now()) return null
  return { kind: p.kind, hours: p.hours, amount: p.amount, addKm: p.addKm || 0, requestedAt: p.requestedAt, expiresAt: p.expiresAt }
}

export type ConfirmResult =
  | { ok: true; ride: any }
  | { ok: false; status: number; code: 'NO_PENDING_EXTENSION' | 'EXTENSION_CHANGED' | 'EXTENSION_DETAILS_REQUIRED'; error: string; pendingExtension?: any }

/**
 * Applies the pending extension once — and only the one the rider saw: the
 * confirm must carry its requestedAt (and amount, when sent), and the update
 * matches them, so a request replaced between the rider's screen and their tap
 * is never charged (409 EXTENSION_CHANGED, with the current one to re-show).
 * `apply(p)` returns the extra $set / $inc for the service.
 */
export async function confirmExtension(
  rideId: any, kind: 'rental' | 'hire', seen: { requestedAt?: any; amount?: any },
  apply: (p: any) => { set?: any; inc?: any },
): Promise<ConfirmResult> {
  const ride: any = await Ride.findById(rideId).lean()
  const p = livePendingExtension(ride)
  if (!ride || !p || p.kind !== kind) return { ok: false, status: 409, code: 'NO_PENDING_EXTENSION', error: 'No extension is waiting for your confirmation' }
  const raw = seen?.requestedAt
  let seenAt = raw != null && raw !== '' ? new Date(typeof raw === 'number' ? raw : String(raw)) : null
  // Installed rider apps (≤ v1.5.0) send no requestedAt. Until they are updated
  // (then set STRICT_EXTENSION_CONFIRM=1), accept the current request only if it
  // has been on screen ≥ 10 s, so a request swapped just before the tap is refused.
  if (!seenAt && process.env.STRICT_EXTENSION_CONFIRM !== '1') {
    if (Date.now() - new Date(p.requestedAt).getTime() < 10_000) {
      return { ok: false, status: 409, code: 'EXTENSION_CHANGED', error: 'The extension changed. Please check the new price and confirm again.', pendingExtension: p }
    }
    seenAt = new Date(p.requestedAt)
  }
  if (!seenAt || !Number.isFinite(seenAt.getTime())) {
    return { ok: false, status: 400, code: 'EXTENSION_DETAILS_REQUIRED', error: 'Send the requestedAt (and amount) of the extension you are confirming', pendingExtension: p }
  }
  const changed = { ok: false as const, status: 409, code: 'EXTENSION_CHANGED' as const, error: 'The extension changed. Please check the new price and confirm again.', pendingExtension: p }
  if (seenAt.getTime() !== new Date(p.requestedAt).getTime()) return changed
  if (seen.amount != null && seen.amount !== '' && Number(seen.amount) !== Number(p.amount)) return changed
  const { set = {}, inc = {} } = apply(p)
  const done = await Ride.findOneAndUpdate(
    {
      _id: rideId, status: 'ongoing',
      'pendingExtension.requestedAt': seenAt,
      'pendingExtension.amount': p.amount,
      'pendingExtension.hours': p.hours,
      'pendingExtension.expiresAt': { $gte: new Date() },
    },
    {
      $set: set,
      $inc: { fare: p.amount, ...inc },
      $unset: { pendingExtension: 1 },
      $push: { extensions: { kind, hours: p.hours, amount: p.amount, addKm: p.addKm || 0, requestedAt: p.requestedAt, confirmedAt: new Date() } },
    },
    { new: true },
  )
  if (!done) {
    const cur: any = await Ride.findById(rideId).select('pendingExtension status').lean()
    const live = livePendingExtension(cur)
    if (live) return { ...changed, pendingExtension: live }
    return { ok: false, status: 409, code: 'NO_PENDING_EXTENSION', error: 'No extension is waiting for your confirmation' }
  }
  return { ok: true, ride: done }
}
