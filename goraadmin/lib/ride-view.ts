// What a DRIVER may read of a ride. The pickup OTP and the parcel drop OTP are
// read out by the rider / receiver; a driver who could fetch them would make
// the check pointless. Every driver-facing ride response goes through here.
import { NextRequest } from 'next/server'
import { requireAdmin, requireDriverAuth, requireRider } from './auth'

import { randomBytes } from 'crypto'

const DRIVER_HIDDEN = [
  'otp', 'dropOtp', 'otpAttempts', 'dropOtpAttempts', 'receiverPhoneNorm', 'refundLeaseAt',
  // The rider's money / promo / share link are none of the driver's business.
  'couponCode', 'couponSource', 'onlinePayment', 'prepaidRef', 'prepaidVia', 'prepaidUnlinked',
  'prepaidCaptured', 'prepaidExcessRefunded', 'shareToken', 'clientRequestId', 'issueReports',
  'refundAttempts', 'refundNextAt', 'unreachableCancelAt',
] as const

/** Phone fields on a ride, shown only while the trip is live (accepted/arrived/ongoing). */
export const RIDE_PHONE_FIELDS = ['riderPhone', 'senderPhone', 'receiverPhone', 'driverPhone'] as const

export function driverSafeRide<T extends Record<string, any>>(ride: T): T {
  if (!ride) return ride
  const out: any = { ...ride }
  for (const k of DRIVER_HIDDEN) delete out[k]
  // Split payers are the rider's contacts: never their phone numbers.
  if (Array.isArray(out.splitRequests)) {
    out.splitRequests = out.splitRequests.map((s: any) => {
      const { phone: _p, phoneNorm: _n, payerPhone: _pp, ...rest } = s || {}
      return rest
    })
  }
  return out
}

/** Removes every phone number from a ride (and its delivery stops) — for a ride that is not live. */
export function withoutPhones<T extends Record<string, any>>(ride: T): T {
  if (!ride) return ride
  const out: any = { ...ride }
  for (const k of RIDE_PHONE_FIELDS) delete out[k]
  if (Array.isArray(out.deliveryStops)) out.deliveryStops = out.deliveryStops.map(({ receiverPhone: _r, ...s }: any) => s)
  return out
}

// ── Share link ───────────────────────────────────────────────────────────────
/** A fresh public share token: 24 random bytes (192 bit), url-safe. */
export function newShareToken(): string {
  return randomBytes(24).toString('base64url')
}
/** Plausible share token shape (avoids a DB lookup for junk). */
export function isShareToken(t: any): boolean {
  return typeof t === 'string' && /^[A-Za-z0-9_-]{22,64}$/.test(t)
}

// ── Review flags and new bookings ────────────────────────────────────────────
/** A ride flagged needsReview this long ago no longer stops its rider booking again. */
export const REVIEW_BLOCK_GRACE_MS = 30 * 60_000
const BLOCKING_STATUSES = ['pending', 'accepted', 'arrived', 'ongoing']

/**
 * Does this ride stop its rider booking another one? Yes while it is
 * pending/accepted/arrived/ongoing — unless it was flagged needsReview more
 * than REVIEW_BLOCK_GRACE_MS ago (a stuck ride an admin has not resolved yet
 * must not lock the rider out). rides/book applies this to its active-ride
 * lookup (together with its own "scheduled for later" exception).
 */
export function blocksNewBooking(ride: any, now: Date = new Date()): boolean {
  if (!ride || !BLOCKING_STATUSES.includes(ride.status)) return false
  if (ride.needsReview === true) {
    const at = ride.needsReviewAt ? new Date(ride.needsReviewAt).getTime() : 0
    if (now.getTime() - at >= REVIEW_BLOCK_GRACE_MS) return false
  }
  return true
}

/** Mongo filter twin of blocksNewBooking's review exception (AND it into the active-ride query). */
export function notStaleReviewFilter(now: Date = new Date()): Record<string, any> {
  return { $or: [{ needsReview: { $ne: true } }, { needsReviewAt: { $gt: new Date(now.getTime() - REVIEW_BLOCK_GRACE_MS) } }] }
}

export type RideActor = { role: 'rider' | 'driver' | 'admin'; id: string }

/**
 * Who is calling about this ride, derived from the token only:
 *   rider token  → 'rider'  (must be the ride's rider)
 *   driver token → 'driver' (must be the ride's assigned driver)
 *   admin token  → 'admin'
 * Returns { actor } or { status, error } to return as-is.
 */
export function rideActor(
  req: NextRequest,
  ride: { riderId?: any; driverId?: any },
): { actor: RideActor } | { status: number; error: string; code: string } {
  const d = requireDriverAuth(req) as any
  if (d?.id) {
    if (ride.driverId && String(ride.driverId) === String(d.id)) return { actor: { role: 'driver', id: String(d.id) } }
    return { status: 403, error: 'Not your ride', code: 'NOT_PARTICIPANT' }
  }
  const u = requireRider(req) as any
  if (u?.id) {
    if (ride.riderId && String(ride.riderId) === String(u.id)) return { actor: { role: 'rider', id: String(u.id) } }
    return { status: 403, error: 'Not your ride', code: 'NOT_PARTICIPANT' }
  }
  const a = requireAdmin(req) as any
  if (a?.id) return { actor: { role: 'admin', id: String(a.id) } }
  return { status: 401, error: 'Unauthorized', code: 'UNAUTHORIZED' }
}

export const ACTIVE_STATUSES = ['accepted', 'arrived', 'ongoing']

/**
 * An uploaded file reference, normalised to its relative "/uploads/<name>"
 * path, or null when it is anything else. The apps send either the relative
 * path /api/upload returned or that path prefixed with the server base URL
 * (AppConfig.imageUrl); only the path is kept, so a foreign host can never be
 * stored. The apps' imageUrl() turns the relative path back into a full URL.
 */
export function uploadPath(u: any): string | null {
  if (typeof u !== 'string' || u.length > 400) return null
  let path = u.trim()
  if (/^https?:\/\//i.test(path)) {
    try { path = new URL(path).pathname } catch { return null }
  }
  // /uploads/<file> (public) or /api/files/<name> (private uploads, served with auth).
  const ok = /^\/uploads\/[A-Za-z0-9._\-\/]+$/.test(path) || /^\/api\/files\/[A-Za-z0-9._\-]+$/.test(path)
  if (!ok || path.includes('..')) return null
  return path
}
export function isUploadPath(u: any): boolean { return uploadPath(u) !== null }

/**
 * The value to STORE for an uploaded-file reference sent by an app, or null
 * when it is not one: a relative /uploads/… path as-is, or a full URL as-is
 * when it points at THIS server (its host is the request's host) and its path
 * is an /uploads/… file. Kept verbatim so app screens that show the stored
 * URL directly keep working.
 */
export function uploadRef(u: any, req: NextRequest): string | null {
  const path = uploadPath(u)
  if (!path) return null
  const raw = String(u).trim()
  if (!/^https?:\/\//i.test(raw)) return path
  try {
    const host = new URL(raw).host.toLowerCase()
    const own = [req.headers.get('x-forwarded-host'), req.headers.get('host'), req.nextUrl?.host]
      .filter(Boolean).map(h => String(h).split(',')[0].trim().toLowerCase())
    return own.includes(host) ? raw : path
  } catch { return null }
}
