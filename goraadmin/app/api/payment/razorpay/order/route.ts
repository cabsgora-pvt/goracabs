export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { requireActiveRider } from '@/lib/auth'
import { connectDB } from '@/lib/mongodb'
import { withCors, corsOptions } from '@/lib/cors'
import { createRazorpayOrder } from '@/lib/razorpay'
import Ride from '@/models/Ride'

export async function OPTIONS() { return corsOptions() }

const PURPOSES = new Set(['wallet', 'ride', 'outstation_prepay'])
const MAX_AMOUNT = 100000

// POST /api/payment/razorpay/order  body: { amount, purpose, rideId? }
//   purpose 'wallet'            → wallet top-up of `amount`
//   purpose 'outstation_prepay' → outstation fare paid BEFORE booking (no ride yet)
//   purpose 'ride' + rideId     → pay that ride; the amount is the SERVER's
//                                 ride.amountDue (the client's amount is ignored)
//   purpose 'ride' without rideId → legacy outstation prepay (old app builds)
// Every order is stamped with notes { userId, purpose, rideId? } which verify,
// lib/prepay and refunds check against Razorpay's copy of the order.
// → { orderId, keyId, amount (paise), currency }
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveRider(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)
    const payload = { id: auth.id }

    const body = await req.json().catch(() => ({}))
    const purpose = String(body.purpose || 'wallet')
    if (!PURPOSES.has(purpose)) return withCors({ error: 'Invalid purpose' }, 400)
    const rideId = body.rideId ? String(body.rideId) : ''
    let amt = Math.round(Number(body.amount) || 0)

    if (rideId) {
      if (purpose !== 'ride') return withCors({ error: 'rideId is only for ride payments' }, 400)
      if (!mongoose.isValidObjectId(rideId)) return withCors({ error: 'Ride not found' }, 404)
      await connectDB()
      const ride: any = await Ride.findById(rideId).select('riderId paymentMode paymentStatus status amountDue').lean()
      if (!ride) return withCors({ error: 'Ride not found' }, 404)
      if (String(ride.riderId || '') !== String(payload.id)) return withCors({ error: 'Not your ride' }, 403)
      if (ride.paymentStatus === 'paid') return withCors({ error: 'This ride is already paid', code: 'alreadyPaid' }, 400)
      if (ride.paymentMode !== 'online') return withCors({ error: 'This ride is not an online-payment ride', code: 'notOnline', paymentMode: ride.paymentMode }, 400)
      if (ride.status === 'cancelled') return withCors({ error: 'This ride was cancelled' }, 400)
      // The server's figure once it has one (request-payment / complete).
      if (ride.amountDue != null && Number(ride.amountDue) > 0) amt = Math.round(Number(ride.amountDue))
    }
    if (amt <= 0 || amt > MAX_AMOUNT) return withCors({ error: 'Invalid amount' }, 400)

    const receipt = `${purpose}_${payload.id}_${Date.now()}`.slice(0, 40)
    const notes: Record<string, string> = { userId: String(payload.id), purpose }
    if (rideId) notes.rideId = rideId
    const result = await createRazorpayOrder(amt, receipt, notes)
    if (!result.ok) return withCors({ error: result.error }, 502)

    return withCors({
      orderId: result.order.id,
      keyId: result.keyId,
      amount: result.order.amount,
      currency: result.order.currency,
    })
  } catch {
    return withCors({ error: 'Failed to create order' }, 500)
  }
}
