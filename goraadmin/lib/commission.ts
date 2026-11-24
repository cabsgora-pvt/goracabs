// ─────────────────────────────────────────────────────────────────────────────
// Commission: who pays what, and the franchise's part of it.
//
// Rate (both modes):
//   • a driver with an active subscription pays the plan's
//     commissionPercentWhileActive (normally 0);
//   • otherwise the zone pricing commission for that vehicle + service, fixed
//     on the ride when it was booked (rides/book).
// The same rule is used for the whole ride (/complete) and for split-fare
// shares paid early (/split/pay), so a subscribed driver never pays
// commission on part of a fare.
//
// Franchise mode ON, and the ride's zone is held by a zone admin whose access
// is active (or in its read-only grace period):
//   • of each ride's commission, the zone admin's revenueSharePercent is theirs,
//     the rest is Gora's;
//   • a subscribed driver pays no ride commission, so instead the zone admin
//     gets the same % of the subscription price the driver paid while in their
//     zone.
// Each share is SNAPSHOTTED when it is earned (zone admin, %, base, ₹), so a
// later change of %, zones or mode never rewrites past months. Franchise mode
// OFF (or no eligible zone admin): the snapshot records ₹0 and all of it is
// Gora's. Nothing is paid automatically: lib/zone-admin computeSettlement adds
// the snapshots up per month and the super admin records payouts.
// ─────────────────────────────────────────────────────────────────────────────
import mongoose from 'mongoose'
import Zone from '@/models/Zone'
import ZoneAdmin from '@/models/ZoneAdmin'
import { isFranchiseMode } from './franchise'
import { accessState } from './zone-admin'

/** The fallback when a ride has no commission % and its zone sets none. */
export const DEFAULT_COMMISSION_PERCENT = 20

export function hasActiveSubscription(driver: any, now = Date.now()): boolean {
  return !!(driver && driver.subscriptionActive && driver.subscriptionExpiresAt
    && new Date(driver.subscriptionExpiresAt).getTime() > now)
}

/** The commission % this driver pays on this ride. */
export async function commissionPercentFor(driver: any, ride: any): Promise<number> {
  if (hasActiveSubscription(driver)) return Math.max(0, Number(driver.subscriptionCommissionPercent) || 0)
  if (ride.commissionPercent != null) return ride.commissionPercent
  const zone: any = ride.zoneId ? await Zone.findById(ride.zoneId).select('pricing').lean() : null
  const p = zone?.pricing?.find((x: any) => x.vehicleTypeName === ride.vehicleType && x.service === ride.service)
  return p?.commissionPercent != null ? p.commissionPercent : DEFAULT_COMMISSION_PERCENT
}

export type FranchiseShare = {
  zoneAdminId: mongoose.Types.ObjectId | null
  zoneId: mongoose.Types.ObjectId | null
  percent: number
  base: number     // ₹ the % applies to (ride commission, or subscription price)
  amount: number   // ₹ owed to the zone admin
  at: Date
}

/**
 * The franchise share of `base` ₹ earned in `zoneId` right now. Always returns
 * a snapshot — ₹0 with zoneAdminId null when franchise mode is off or no
 * eligible zone admin holds the zone.
 */
export async function franchiseShareFor(zoneId: any, base: number): Promise<FranchiseShare> {
  const at = new Date()
  const zid = zoneId && mongoose.isValidObjectId(String(zoneId)) ? new mongoose.Types.ObjectId(String(zoneId)) : null
  const none: FranchiseShare = { zoneAdminId: null, zoneId: zid, percent: 0, base: Math.max(0, base || 0), amount: 0, at }
  if (!zid || !(base > 0)) return none
  if (!(await isFranchiseMode())) return none
  const admin: any = await ZoneAdmin.findOne({ zoneIds: zid }).select('status subscriptionEndAt revenueSharePercent').lean()
  if (!admin) return none
  const state = accessState(admin)
  if (state !== 'active' && state !== 'grace') return none
  const percent = Math.min(100, Math.max(0, Number(admin.revenueSharePercent) || 0))
  const amount = Math.round(base * percent) / 100
  return { zoneAdminId: admin._id, zoneId: zid, percent, base, amount, at }
}
