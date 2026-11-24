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
//   rider   { action: 'confirm_extend' }      → applied atomically: hours added,
//           `fare` += amount, entry appended to ride.extensions
//   rider   { action: 'decline_extend' }      → pendingExtension cleared
// A pending request expires after EXTENSION_TTL_MS; a new 'extend' replaces it.
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

/** Stores a driver's extension request for the rider to confirm. */
export async function requestExtension(ride: any, kind: 'rental' | 'hire', hours: number, amount: number, addKm = 0) {
  const now = new Date()
  const pendingExtension = { kind, hours, amount, addKm, requestedAt: now, expiresAt: new Date(now.getTime() + EXTENSION_TTL_MS) }
  await Ride.updateOne({ _id: ride._id, status: 'ongoing' }, { $set: { pendingExtension } })
  return pendingExtension
}

export function livePendingExtension(ride: any): any | null {
  const p = ride?.pendingExtension
  if (!p || !p.hours) return null
  if (p.expiresAt && new Date(p.expiresAt).getTime() < Date.now()) return null
  return { kind: p.kind, hours: p.hours, amount: p.amount, addKm: p.addKm || 0, requestedAt: p.requestedAt, expiresAt: p.expiresAt }
}

/**
 * Applies the pending extension once (atomic on the pending request itself).
 * `apply(ride)` returns the extra $set / $inc for the service.
 */
export async function confirmExtension(rideId: any, kind: 'rental' | 'hire', apply: (p: any) => { set?: any; inc?: any }) {
  const ride: any = await Ride.findById(rideId).lean()
  const p = livePendingExtension(ride)
  if (!ride || !p || p.kind !== kind) return null
  const { set = {}, inc = {} } = apply(p)
  const done = await Ride.findOneAndUpdate(
    { _id: rideId, status: 'ongoing', 'pendingExtension.requestedAt': ride.pendingExtension.requestedAt },
    {
      $set: set,
      $inc: { fare: p.amount, ...inc },
      $unset: { pendingExtension: 1 },
      $push: { extensions: { kind, hours: p.hours, amount: p.amount, addKm: p.addKm || 0, requestedAt: p.requestedAt, confirmedAt: new Date() } },
    },
    { new: true },
  )
  return done
}
