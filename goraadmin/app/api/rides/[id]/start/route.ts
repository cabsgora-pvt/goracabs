export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkRideOtp } from '@/lib/ride-otp'

export async function OPTIONS() { return corsOptions() }

// POST { otp } → start ride if OTP matches
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { otp } = await req.json().catch(() => ({}))
    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    // Only the assigned driver, and only before the trip has started.
    if (!ride.driverId || String(ride.driverId) !== String(payload.id)) {
      return withCors({ error: 'Not your ride' }, 403)
    }
    // A repeat of a start that went through but whose answer was lost.
    if (ride.status === 'ongoing') return withCors({ success: true, repeated: true })
    if (!['accepted', 'arrived'].includes(ride.status)) {
      return withCors({ error: `Ride cannot be started (status: ${ride.status})` }, 400)
    }
    if (!ride.otp) return withCors({ error: 'This ride has no OTP. Please contact support.', code: 'OTP_MISSING' }, 409)
    if (ride.otpLocked) {
      return withCors({ error: 'Too many wrong OTPs — this code is locked. Ask the customer to contact support.', code: 'OTP_LOCKED', otpLocked: true }, 423)
    }

    // Attempt-limited, race-safe check (lib/ride-otp.ts).
    const chk = await checkRideOtp(ride._id, 'otp', otp, String(payload.id))
    if (!chk.ok) {
      const { status, ok: _ok, ...body } = chk as any
      return withCors({ ...body, ...(chk.code === 'OTP_LOCKED' ? { otpLocked: true } : {}) }, status)
    }

    // Atomic on status, so two correct starts cannot both run.
    const started = await Ride.findOneAndUpdate(
      // unreachableCancelAt: the rider reported the driver unreachable and the
      // ride is being cancelled (rides/{id}/report-issue) — it must not start.
      { _id: ride._id, driverId: ride.driverId, status: { $in: ['accepted', 'arrived'] }, unreachableCancelAt: null },
      { $set: { status: 'ongoing', startedAt: new Date(), ...(ride.service === 'outstation' ? { outstationPhase: 'enroute' } : {}) } },
      { new: true },
    ).select('_id').lean()
    if (!started) {
      const now: any = await Ride.findById(ride._id).select('status unreachableCancelAt').lean()
      if (now?.status === 'cancelled' || now?.unreachableCancelAt) {
        return withCors({ error: 'This ride was cancelled', code: 'RIDE_CANCELLED' }, 409)
      }
      return withCors({ success: true, repeated: true })
    }
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
