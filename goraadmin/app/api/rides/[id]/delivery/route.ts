export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/delivery  body.action:
//  'collected'           → driver collected parcel from sender (after sender OTP start), phase in_transit
//  'deliver' { dropOtp } → verify receiver OTP, mark delivered + completed
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    if (b.action === 'collected') {
      ride.deliveryPhase = 'in_transit'
    } else if (b.action === 'deliver') {
      if ((b.dropOtp || '').toString().trim() !== (ride.dropOtp || '')) {
        return withCors({ error: 'Invalid delivery OTP' }, 400)
      }
      ride.deliveryPhase = 'delivered'
      ride.status = 'completed'
      ride.completedAt = new Date()
    }
    await ride.save()
    return withCors({ success: true, deliveryPhase: ride.deliveryPhase, status: ride.status })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
