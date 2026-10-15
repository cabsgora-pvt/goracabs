import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import FaceVerification from '@/models/FaceVerification'

// Resolves any of this driver's pending mid-ride face checks whose deadline
// has passed, as a no-response failure. Hooked into both the ride poll
// (face-check) and the location ping — the latter so a driver who kills the
// app right after the prompt appears still gets swept (the foreground
// service keeps pushing location even with the UI closed; it won't keep
// polling face-check if that screen was never reached).
export async function sweepOverdueFaceVerification(driverId: string) {
  const now = new Date()
  const overdue = await FaceVerification.find({
    driverId, status: 'pending', deadlineAt: { $lt: now },
  }).lean()
  if (overdue.length === 0) return

  for (const attempt of overdue) {
    await FaceVerification.findByIdAndUpdate(attempt._id, { status: 'no_response', respondedAt: now })
    if (attempt.rideId) {
      await Ride.findByIdAndUpdate(attempt.rideId, {
        status: 'cancelled',
        cancelledBy: 'system',
        cancellationReason: 'face_verification_failed',
      })
    }
  }
  await Driver.findByIdAndUpdate(driverId, {
    faceVerificationRequired: true,
    faceVerificationReason: 'no_response',
  })
}
