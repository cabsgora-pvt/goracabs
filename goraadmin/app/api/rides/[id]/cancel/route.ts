export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { cancelledBy, reason } → cancel ride
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const { cancelledBy, reason } = await req.json()
    await connectDB()
    const ride: any = await Ride.findByIdAndUpdate(
      params.id,
      { $set: { status: 'cancelled', cancelledBy: cancelledBy || 'rider', cancellationReason: reason || '' } },
      { new: true }
    )
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
