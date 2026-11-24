// What a DRIVER may read of a ride. The pickup OTP and the parcel drop OTP are
// read out by the rider / receiver; a driver who could fetch them would make
// the check pointless. Every driver-facing ride response goes through here.
import { NextRequest } from 'next/server'
import { requireAdmin, requireDriverAuth, requireRider } from './auth'

const DRIVER_HIDDEN = ['otp', 'dropOtp', 'otpAttempts', 'dropOtpAttempts', 'receiverPhoneNorm', 'refundLeaseAt'] as const

export function driverSafeRide<T extends Record<string, any>>(ride: T): T {
  if (!ride) return ride
  const out: any = { ...ride }
  for (const k of DRIVER_HIDDEN) delete out[k]
  return out
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
  if (!/^\/uploads\/[A-Za-z0-9._\-\/]+$/.test(path) || path.includes('..')) return null
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
