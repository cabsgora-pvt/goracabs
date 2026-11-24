import Driver from '@/models/Driver'
import FaceVerification from '@/models/FaceVerification'
import { cancelRide } from '@/lib/refunds'
import { pushToUserAsync } from '@/lib/push'

// Resolves pending mid-ride face checks whose deadline has passed, as a
// no-response failure. Hooked into the ride poll (face-check), the location
// ping (the foreground service keeps pinging even with the UI closed), and
// POST /api/cron/dispatch for every driver.
//
// The ride is cancelled through lib/refunds cancelRide — the same atomic
// cancel as the rider/admin path — so any money captured upfront is refunded
// (or flagged for review) and the rider is told, instead of the ride just being
// flipped to 'cancelled' with nothing given back.
async function resolveOverdue(attempts: any[], now: Date) {
  const drivers = new Set<string>()
  for (const attempt of attempts) {
    // Claim it so two sweeps never resolve the same attempt twice.
    const claimed = await FaceVerification.findOneAndUpdate(
      { _id: attempt._id, status: 'pending' },
      { $set: { status: 'no_response', respondedAt: now } },
      { new: true },
    ).lean()
    if (!claimed) continue
    drivers.add(String(attempt.driverId))
    if (attempt.rideId) {
      try {
        const out: any = await cancelRide(attempt.rideId, 'system', 'face_verification_failed')
        if (out?.ride && !out.alreadyCancelled) {
          pushToUserAsync(out.ride.riderId, {
            title: 'Ride cancelled',
            body: 'Your driver could not complete a safety check, so this ride was cancelled. Any amount paid is refunded.',
            channelId: 'ride_updates',
            data: { type: 'ride_cancelled', rideId: String(out.ride._id), cancelledBy: 'system', reason: 'face_verification_failed' },
          })
        }
      } catch (e) { console.error('[face-sweep] cancel failed', e) }
    }
  }
  for (const id of Array.from(drivers)) {
    await Driver.findByIdAndUpdate(id, { faceVerificationRequired: true, faceVerificationReason: 'no_response' })
  }
  return drivers.size
}

export async function sweepOverdueFaceVerification(driverId: string) {
  const now = new Date()
  const overdue = await FaceVerification.find({ driverId, status: 'pending', deadlineAt: { $lt: now } }).lean()
  if (overdue.length === 0) return
  await resolveOverdue(overdue, now)
}

/** Every driver's overdue checks (bounded). Returns how many drivers were locked. */
export async function sweepAllOverdueFaceVerification(limit = 100): Promise<number> {
  const now = new Date()
  const overdue = await FaceVerification.find({ status: 'pending', deadlineAt: { $lt: now } }).limit(limit).lean()
  if (!overdue.length) return 0
  return resolveOverdue(overdue, now)
}
