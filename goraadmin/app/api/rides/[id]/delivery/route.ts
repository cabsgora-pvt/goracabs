export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { checkRideOtp } from '@/lib/ride-otp'
import { uploadRef } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/delivery  body.action — ASSIGNED DRIVER ONLY, ride 'ongoing':
//  'collected' { lat?, lng? }                   pending   → in_transit (anchor distance)
//  'ping'      { lat, lng }                     in_transit: accumulate deliveryDistance
//  'deliver'   { dropOtp, proofPhoto?, signature? }
//                                               in_transit → delivered (receiver's OTP,
//                                               attempt-limited: 5 wrong → 423 locked)
//  'failed'    { reason, photoUrl }             in_transit → returned (return to sender);
//                                               reason (3..300 chars) and an /uploads/
//                                               proof photo are required
//
// Phases only move forward (pending → collected/in_transit → delivered | returned).
// Once delivered or returned nothing here changes the ride again. The rider
// app can no longer call any of these (they used to pass guardRideActor).
//
// NEITHER terminal action completes the ride: price here, collect in the app,
// settle in /rides/{id}/complete. Both return `amountDue`, what the driver
// must take at the door: the delivery fare (cash only) plus COD on a handover.
const TERMINAL = new Set(['delivered', 'failed', 'returned'])
const MAX_PING_KM = 5

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const d = requireDriverAuth(req) as any
    if (!d?.id) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const b = await req.json().catch(() => ({}))
    const action = String(b?.action || '')
    if (!['collected', 'ping', 'deliver', 'failed'].includes(action)) return withCors({ error: 'Unknown action' }, 400)

    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (!ride.driverId || String(ride.driverId) !== String(d.id)) return withCors({ error: 'Not your ride' }, 403)
    if (ride.service !== 'delivery') return withCors({ error: 'Not a delivery' }, 400)
    if (ride.status !== 'ongoing') {
      return withCors({ error: `Delivery actions need the trip started (status: ${ride.status})`, code: 'NOT_ONGOING' }, 409)
    }
    const phase = ride.deliveryPhase || 'pending'
    if (TERMINAL.has(phase)) {
      return withCors({ error: `This delivery is already ${phase}`, code: 'DELIVERY_FINISHED', deliveryPhase: phase }, 409)
    }

    const num = (v: any) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
    const lat = num(b.lat), lng = num(b.lng)
    const validFix = lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0)

    if (action === 'collected') {
      if (phase === 'in_transit' || phase === 'collected') {
        return withCors({ success: true, repeated: true, deliveryPhase: phase, status: ride.status })
      }
      ride.deliveryPhase = 'in_transit'
      ride.collectedAt = new Date()
      ride.deliveryLastLat = validFix ? lat : ride.pickupLat
      ride.deliveryLastLng = validFix ? lng : ride.pickupLng
    } else {
      // Everything else needs the parcel picked up first.
      if (phase === 'pending') {
        return withCors({ error: 'Collect the parcel first', code: 'NOT_COLLECTED', deliveryPhase: phase }, 409)
      }
      if (action === 'ping') {
        if (validFix && ride.deliveryLastLat != null) {
          const km = distanceKm({ lat: ride.deliveryLastLat, lng: ride.deliveryLastLng }, { lat: lat!, lng: lng! })
          if (km > 0.02 && km <= MAX_PING_KM) {
            ride.deliveryDistance = +((ride.deliveryDistance || 0) + km).toFixed(2)
            ride.deliveryLastLat = lat; ride.deliveryLastLng = lng
          }
        }
      } else if (action === 'failed') {
        const reason = typeof b.reason === 'string' ? b.reason.trim() : ''
        if (reason.length < 3 || reason.length > 300) return withCors({ error: 'Tell us why the delivery failed', code: 'REASON_REQUIRED' }, 400)
        const photo = uploadRef(b.photoUrl ?? b.proofPhoto, req)
        if (!photo) return withCors({ error: 'A photo is required to mark a delivery as failed', code: 'PHOTO_REQUIRED' }, 400)
        // Return to sender. The driver still drove the job, so the delivery fare
        // stands — but the receiver never accepted the parcel, so NO cash-on-
        // delivery is collected and none is owed to the sender.
        const set: any = {
          deliveryPhase: 'returned', failReason: reason, deliveryFailPhoto: photo, failedAt: new Date(),
          deliveryFinalFare: Math.round(ride.fare || 0), codCollected: 0,
        }
        set.totalFare = set.deliveryFinalFare + (ride.tip || 0)
        if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') { set.awaitingPayment = true; set.paymentStatus = 'pending' }
        const done = await Ride.findOneAndUpdate(
          { _id: ride._id, driverId: ride.driverId, status: 'ongoing', deliveryPhase: { $in: ['collected', 'in_transit'] } },
          { $set: set }, { new: true })
        if (!done) return withCors({ error: 'This delivery changed — refresh and try again', code: 'DELIVERY_CHANGED' }, 409)
        return answer(done)
      } else if (action === 'deliver') {
        if (!ride.dropOtp) return withCors({ error: 'This parcel has no delivery OTP. Please contact support.', code: 'OTP_MISSING' }, 409)
        if (ride.dropOtpLocked) return withCors({ error: 'Too many wrong OTPs — this code is locked. Ask the customer to contact support.', code: 'OTP_LOCKED', otpLocked: true }, 423)
        const chk = await checkRideOtp(ride._id, 'dropOtp', b.dropOtp, String(d.id))
        if (!chk.ok) {
          const { status, ok: _ok, ...body } = chk as any
          return withCors({ ...body, ...(chk.code === 'OTP_LOCKED' ? { otpLocked: true } : {}) }, status)
        }
        const set: any = { deliveryPhase: 'delivered', deliveredAt: new Date() }
        const proof = b.proofPhoto ? uploadRef(b.proofPhoto, req) : null
        const sign = b.signature ? uploadRef(b.signature, req) : null
        if (proof) set.deliveryProofPhoto = proof
        if (sign) set.deliverySignature = sign
        set.deliveryFinalFare = Math.round(ride.fare || 0)
        // COD is the SENDER's money travelling through the driver — it is not
        // revenue and never attracts commission. Recording what was actually
        // taken keeps "owed" and "collected" distinct for /complete.
        set.codCollected = Math.max(0, Math.round(ride.codAmount || 0))
        set.totalFare = set.deliveryFinalFare + (ride.tip || 0)
        if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') { set.awaitingPayment = true; set.paymentStatus = 'pending' }
        const done = await Ride.findOneAndUpdate(
          { _id: ride._id, driverId: ride.driverId, status: 'ongoing', deliveryPhase: { $in: ['collected', 'in_transit'] } },
          { $set: set }, { new: true })
        if (!done) return withCors({ error: 'This delivery changed — refresh and try again', code: 'DELIVERY_CHANGED' }, 409)
        return answer(done)
      }
    }
    await ride.save()
    return answer(ride)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

function answer(ride: any) {
  // What the driver collects at the door. The delivery fare is only cash-in-
  // hand when the parcel is paid in cash; COD always is.
  const fareDue = ride.paymentMode === 'cash' ? (ride.totalFare || 0) : 0
  const codDue = ride.deliveryPhase === 'delivered' ? (ride.codCollected || 0) : 0
  return withCors({
    success: true,
    deliveryPhase: ride.deliveryPhase,
    status: ride.status,
    fareDue,
    codDue,
    amountDue: fareDue + codDue,
    failReason: ride.failReason || null,
    deliveryDistance: ride.deliveryDistance || 0,
  })
}
