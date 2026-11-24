// ─────────────────────────────────────────────────────────────────────────────
// Ride OTPs (pickup `otp`, parcel `dropOtp`): generation and a guessing guard.
//
// The code is 4 digits because the rider reads it out loud — so the guard, not
// the length, is what stops a driver trying all 10 000:
//   • every check reserves one attempt ATOMICALLY before comparing, so parallel
//     requests cannot get more than MAX_ATTEMPTS compares between them;
//   • after MAX_ATTEMPTS wrong codes the ride's code is locked (HTTP 423) until
//     an admin unlocks it (POST /api/rides/{id}/otp-unlock), which also issues a
//     fresh code;
//   • a driver is additionally limited across ALL rides (PER_DRIVER_* below),
//     so spreading guesses over many rides does not help either.
// ─────────────────────────────────────────────────────────────────────────────
import { randomInt } from 'crypto'
import Ride from '@/models/Ride'

export const RIDE_OTP = {
  MAX_ATTEMPTS: 5,
  PER_DRIVER_WRONG_LIMIT: 10,
  PER_DRIVER_WINDOW_MS: 10 * 60 * 1000,
}

/** A fresh 4-digit ride OTP from a CSPRNG (book uses this for otp and dropOtp). */
export function newRideOtp(): string {
  return String(randomInt(1000, 10000))
}

const wrongByDriver = new Map<string, number[]>()

function driverWrongCount(driverId: string, now = Date.now()): number {
  const since = now - RIDE_OTP.PER_DRIVER_WINDOW_MS
  const list = (wrongByDriver.get(driverId) || []).filter(t => t > since)
  if (list.length) wrongByDriver.set(driverId, list); else wrongByDriver.delete(driverId)
  return list.length
}
function noteWrong(driverId: string) {
  const list = wrongByDriver.get(driverId) || []
  list.push(Date.now())
  wrongByDriver.set(driverId, list)
  if (wrongByDriver.size > 5000) {
    for (const k of Array.from(wrongByDriver.keys())) driverWrongCount(k)
  }
}

export type OtpCheck =
  | { ok: true }
  | { ok: false; status: number; error: string; code: string; attemptsLeft?: number }

/**
 * Checks `given` against the ride's `field` ('otp' | 'dropOtp') for `driverId`.
 * Call only after the caller has verified the driver is assigned to the ride.
 */
export async function checkRideOtp(rideId: any, field: 'otp' | 'dropOtp', given: any, driverId: string): Promise<OtpCheck> {
  const attemptsF = field === 'otp' ? 'otpAttempts' : 'dropOtpAttempts'
  const lockedF = field === 'otp' ? 'otpLocked' : 'dropOtpLocked'

  if (driverWrongCount(driverId) >= RIDE_OTP.PER_DRIVER_WRONG_LIMIT) {
    return { ok: false, status: 429, code: 'OTP_RATE_LIMITED', error: 'Too many wrong OTPs. Please wait a few minutes and try again.' }
  }

  // Reserve one attempt. Fails when locked or out of attempts.
  const ride: any = await Ride.findOneAndUpdate(
    { _id: rideId, [lockedF]: { $ne: true }, [attemptsF]: { $not: { $gte: RIDE_OTP.MAX_ATTEMPTS } } },
    { $inc: { [attemptsF]: 1 } },
    { new: true },
  ).select(`${field} ${attemptsF}`).lean()
  if (!ride) {
    await Ride.updateOne({ _id: rideId }, { $set: { [lockedF]: true } }).catch(() => {})
    return { ok: false, status: 423, code: 'OTP_LOCKED', error: 'Too many wrong OTPs — this code is locked. Ask the customer to contact support.' }
  }

  const expected = String(ride[field] || '')
  if (!expected) {
    return { ok: false, status: 409, code: 'OTP_MISSING', error: 'This ride has no OTP. Please contact support.' }
  }
  const input = String(given ?? '').trim()
  if (input && input === expected) {
    await Ride.updateOne({ _id: rideId }, { $set: { [attemptsF]: 0 } }).catch(() => {})
    return { ok: true }
  }

  noteWrong(driverId)
  const used = Number(ride[attemptsF]) || 0
  if (used >= RIDE_OTP.MAX_ATTEMPTS) {
    await Ride.updateOne({ _id: rideId }, { $set: { [lockedF]: true } })
    return { ok: false, status: 423, code: 'OTP_LOCKED', error: 'Too many wrong OTPs — this code is locked. Ask the customer to contact support.', attemptsLeft: 0 }
  }
  return { ok: false, status: 400, code: 'OTP_INVALID', error: 'Invalid OTP', attemptsLeft: RIDE_OTP.MAX_ATTEMPTS - used }
}

/** Test hook / admin unlock helper: forget a driver's recent wrong guesses. */
export function clearDriverOtpStrikes(driverId: string) { wrongByDriver.delete(driverId) }
