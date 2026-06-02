export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/delivery  body.action:
//  'collected'           → driver collected parcel; phase in_transit (anchor distance)
//  'ping' {lat,lng}      → accumulate deliveryDistance
//  'deliver' { dropOtp } → verify receiver OTP, mark delivered + completed
//  'failed' { reason }   → receiver unavailable → return-to-sender
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
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
      ride.deliveryPhase = 'returned'
      ride.failReason = b.reason || 'Receiver unavailable'
      ride.status = 'completed'
      ride.completedAt = new Date()
    } else if (b.action === 'deliver') {
      if ((b.dropOtp || '').toString().trim() !== (ride.dropOtp || '')) {
        return withCors({ error: 'Invalid delivery OTP' }, 400)
      }
      ride.deliveryPhase = 'delivered'
      ride.status = 'completed'
      ride.completedAt = new Date()
      ride.deliveredAt = new Date()
      if (b.proofPhoto) ride.deliveryProofPhoto = b.proofPhoto
      if (b.signature) ride.deliverySignature = b.signature
    }
    await ride.save()
    return withCors({ success: true, deliveryPhase: ride.deliveryPhase, status: ride.status })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
