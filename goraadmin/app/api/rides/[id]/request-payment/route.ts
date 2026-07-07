export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// Driver ended an ONLINE ride → flag it so the rider is asked to pay.
// The ride is NOT completed here; the rider's app calls /complete after paying,
// which keeps the existing commission logic untouched.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findByIdAndUpdate(
      params.id,
      { awaitingPayment: true, paymentStatus: 'pending' },
      { new: true }
    )
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ success: true, awaitingPayment: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
