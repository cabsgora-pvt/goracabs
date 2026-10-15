export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'
import { guardRideActor } from '@/lib/admin-guard'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/delivery  body.action:
//  'collected'           → driver collected parcel; phase in_transit (anchor distance)
//  'ping' {lat,lng}      → accumulate deliveryDistance
//  'deliver' { dropOtp } → verify receiver OTP, mark delivered, price the job
//  'failed' { reason }   → receiver unavailable → return-to-sender
//
// NEITHER terminal action completes the ride. Both used to set
// status = 'completed' inline, which skipped /rides/{id}/complete entirely —
// so a parcel delivery never produced a commission, never wrote a Transaction
// and never moved a rupee of wallet. Rentals had the same bug and were fixed the
// same way: price here, collect in the app, settle in /complete.
//
// Both actions return `amountDue`, which is what the driver must actually take
// at the door: the delivery fare (cash only) plus any COD on a real handover.
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
    const b = await req.json()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    if (b.action === 'collected') {
      ride.deliveryPhase = 'in_transit'
      ride.deliveryLastLat = b.lat ?? ride.pickupLat
      ride.deliveryLastLng = b.lng ?? ride.pickupLng
    } else if (b.action === 'ping') {
      if (b.lat != null && ride.deliveryLastLat != null) {
        const d = distanceKm({ lat: ride.deliveryLastLat, lng: ride.deliveryLastLng }, { lat: b.lat, lng: b.lng })
        if (d > 0.02) { ride.deliveryDistance = +(ride.deliveryDistance + d).toFixed(2); ride.deliveryLastLat = b.lat; ride.deliveryLastLng = b.lng }
      }
    } else if (b.action === 'failed') {
      // Return to sender. The driver still drove the job, so the delivery fare
      // stands — but the receiver never accepted the parcel, so NO cash-on-
      // delivery is collected and none is owed to the sender.
      ride.deliveryPhase = 'returned'
      ride.failReason = b.reason || 'Receiver unavailable'
      ride.deliveryFinalFare = Math.round(ride.fare || 0)
      ride.codCollected = 0
      ride.totalFare = ride.deliveryFinalFare + (ride.tip || 0)
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    } else if (b.action === 'deliver') {
      if ((b.dropOtp || '').toString().trim() !== (ride.dropOtp || '')) {
        return withCors({ error: 'Invalid delivery OTP' }, 400)
      }
      ride.deliveryPhase = 'delivered'
      ride.deliveredAt = new Date()
      if (b.proofPhoto) ride.deliveryProofPhoto = b.proofPhoto
      if (b.signature) ride.deliverySignature = b.signature

      ride.deliveryFinalFare = Math.round(ride.fare || 0)
      // COD is the SENDER's money travelling through the driver — it is not
      // revenue and never attracts commission. Recording what was actually
      // taken (rather than reusing codAmount) keeps "owed" and "collected"
      // distinct, which is what /complete needs to move it safely.
      ride.codCollected = Math.max(0, Math.round(ride.codAmount || 0))
      ride.totalFare = ride.deliveryFinalFare + (ride.tip || 0)
      if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') {
        ride.awaitingPayment = true
        ride.paymentStatus = 'pending'
      }
    }
    await ride.save()

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
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
