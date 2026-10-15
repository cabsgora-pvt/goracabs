export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import ServiceConfig from '@/models/ServiceConfig'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync, pushToDriverAsync } from '@/lib/push'
import { guardRideActor } from '@/lib/admin-guard'

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
    {
      const _r: any = await Ride.findById(params.id).select('riderId driverId').lean()
      if (!_r) return withCors({ error: 'Ride not found' }, 404)
      const _denied = guardRideActor(req, _r)
      if (_denied) return withCors(await _denied.json(), _denied.status)
    }

    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status === 'completed') return withCors({ error: 'Ride already completed' }, 400)
    if (ride.status === 'cancelled') return withCors({ success: true, alreadyCancelled: true })

    const by = cancelledBy || 'rider'
    let cancellationFee = 0

    // Only charge the rider once a driver has actually committed to the trip.
    // Cancelling a still-pending request stays free.
    const driverWasCommitted = ['accepted', 'arrived'].includes(ride.status)
    if (by === 'rider' && driverWasCommitted) {
      const cfg: any = await ServiceConfig.findOne({ service: ride.service }).lean().catch(() => null)
      cancellationFee = Math.max(0, Number(cfg?.cancellationFee) || 0)
    }

    ride.status = 'cancelled'
    ride.cancelledBy = by
    ride.cancellationReason = reason || ''
    ride.cancellationFee = cancellationFee
    ride.awaitingPayment = false
    await ride.save()

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

    return withCors({ success: true, cancellationFee })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
