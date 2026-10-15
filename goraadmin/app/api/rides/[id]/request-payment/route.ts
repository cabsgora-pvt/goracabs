export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync } from '@/lib/push'
import { guardRideActor } from '@/lib/admin-guard'

export async function OPTIONS() {
  return corsOptions()
}

// Driver ended an ONLINE ride → flag it so the rider is asked to pay.
// The ride is NOT completed here; the rider's app calls /complete after paying,
// which keeps the existing commission logic untouched.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()

    // Only this ride's rider, its assigned driver, or an admin may act on it.
    {
      const _r: any = await Ride.findById(params.id).select('riderId driverId').lean()
      if (!_r) return withCors({ error: 'Ride not found' }, 404)
      const _denied = guardRideActor(req, _r)
      if (_denied) return withCors(await _denied.json(), _denied.status)
    }
    const ride: any = await Ride.findByIdAndUpdate(
      params.id,
      { awaitingPayment: true, paymentStatus: 'pending' },
      { new: true }
    )
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    // The driver is standing there waiting to be paid, so this one is worth a
    // high-priority push rather than waiting for the rider's next poll.
    const due = ride.totalFare ?? ride.fare
    pushToUserAsync(ride.riderId, {
      title: 'Payment requested',
      body: due != null ? `Please pay ₹${Math.round(Number(due))} for your ride` : 'Please complete payment for your ride',
      channelId: 'ride_updates',
      data: {
        type: 'payment_requested',
        rideId: String(ride._id),
        ...(due != null ? { amount: String(Math.round(Number(due))) } : {}),
      },
    })

    return withCors({ success: true, awaitingPayment: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
