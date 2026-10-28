export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync, pushToDriverAsync } from '@/lib/push'
import { guardRideActor } from '@/lib/admin-guard'
import { cancelRide } from '@/lib/refunds'
import { requireAuth, requireDriverAuth, isAdminPayload } from '@/lib/auth'

export async function OPTIONS() { return corsOptions() }

// POST { cancelledBy, reason } → cancel ride
//
// Now applies the per-service cancellationFee that admin has always been able
// to configure but which nothing ever read: a rider cancelling after a driver
// had already accepted and started driving to them cost them nothing, and the
// driver was compensated nothing.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const { cancelledBy, reason } = await req.json()
    await connectDB()

    // Only this ride's rider, its assigned driver, or an admin may act on it.
    const _r: any = await Ride.findById(params.id).select('riderId driverId').lean()
    if (!_r) return withCors({ error: 'Ride not found' }, 404)
    const _denied = guardRideActor(req, _r)
    if (_denied) return withCors(await _denied.json(), _denied.status)

    // Who cancelled decides the fee and the refund, so it comes from the
    // caller's token, never from the body: a rider sending cancelledBy:'admin'
    // used to skip the fee (and would now get a full prepaid refund too).
    const asDriver = requireDriverAuth(req) as any
    const asUser = requireAuth(req) as any
    let by: string
    if (asDriver?.type === 'driver' && _r.driverId && String(_r.driverId) === String(asDriver.id)) by = 'driver'
    else if (asUser?.type === 'user' && _r.riderId && String(_r.riderId) === String(asUser.id)) by = 'rider'
    else if (isAdminPayload(asUser)) by = cancelledBy || 'admin'
    else return withCors({ error: 'Not a participant in this ride' }, 403)
    const out = await cancelRide(params.id, by, reason)
    if (out.error) return withCors({ error: out.error }, out.status || 400)
    if (out.alreadyCancelled) return withCors({ success: true, alreadyCancelled: true })
    const { ride, cancellationFee, review, refundedAmount } = out

    // Notify whoever did NOT press cancel. A driver already driving to a pickup
    // is the case that matters — without this they find out by watching the
    // ride vanish from a poll, or not at all if the screen is backgrounded.
    if (by === 'rider') {
      if (ride.driverId) {
        pushToDriverAsync(ride.driverId, {
          title: 'Ride cancelled',
          body: reason ? `Rider cancelled: ${reason}` : 'The rider cancelled this ride',
          channelId: 'ride_updates',
          data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'rider' },
        })
      }
    } else {
      pushToUserAsync(ride.riderId, {
        title: 'Ride cancelled',
        body: reason ? `Your ride was cancelled: ${reason}` : 'Your ride was cancelled',
        channelId: 'ride_updates',
        data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: String(by) },
      })
    }

    return withCors({ success: true, cancellationFee, refundedAmount, ...(review ? { refundReview: review } : {}) })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
