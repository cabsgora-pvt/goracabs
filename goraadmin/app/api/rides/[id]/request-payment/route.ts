export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync } from '@/lib/push'
import { requireDriverAuth } from '@/lib/auth'
import { riderAmountDue } from '@/lib/settlement'

export async function OPTIONS() {
  return corsOptions()
}

// Driver asks the rider to pay an ONLINE ride (assigned driver only; ride
// ongoing or already completed-but-unpaid). Stores the server's amountDue on
// the ride — /payment/razorpay/order charges exactly that — and pushes the
// rider. The ride is completed by /complete; a payment that arrives first is
// held on the ride and applied when it completes.
// → { success, awaitingPayment, amountDue }
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const drv = requireDriverAuth(req) as any
    if (!drv?.id) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()

    const cur: any = await Ride.findById(params.id).lean()
    if (!cur) return withCors({ error: 'Ride not found' }, 404)
    if (!cur.driverId || String(cur.driverId) !== String(drv.id)) return withCors({ error: 'Not a participant in this ride' }, 403)
    if (cur.status !== 'ongoing' && cur.status !== 'completed') {
      return withCors({ error: `Ride is ${cur.status}; payment can be requested only for an ongoing or completed ride` }, 400)
    }
    if (cur.paymentStatus === 'paid') return withCors({ error: 'This ride is already paid', code: 'alreadyPaid' }, 400)

    // A completed ride already has its settled figure; an ongoing one gets the
    // current figure (recomputed again when it completes).
    const due = cur.status === 'completed' && cur.amountDue != null ? Number(cur.amountDue) : riderAmountDue(cur)
    const ride: any = await Ride.findOneAndUpdate(
      { _id: cur._id, status: { $in: ['ongoing', 'completed'] }, paymentStatus: { $ne: 'paid' } },
      { $set: { awaitingPayment: true, paymentStatus: 'pending', amountDue: due } },
      { new: true },
    ).lean() as any
    if (!ride) return withCors({ error: 'The ride changed, please retry' }, 409)

    // The driver is standing there waiting to be paid, so this one is worth a
    // high-priority push rather than waiting for the rider's next poll.
    pushToUserAsync(ride.riderId, {
      title: 'Payment requested',
      body: `Please pay ₹${due} for your ride`,
      channelId: 'ride_updates',
      data: { type: 'payment_requested', rideId: String(ride._id), amount: String(due) },
    })

    return withCors({ success: true, awaitingPayment: true, amountDue: due })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
