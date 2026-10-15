export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { offerNext } from '@/lib/dispatch'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST → driver rejects a pending ride (stays pending for others)
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    await Ride.findByIdAndUpdate(params.id, { $addToSet: { rejectedBy: String(payload.id) } })

    // If this driver was the one holding the offer, don't make the rider wait
    // out the countdown — escalate to the next candidate straight away.
    const ride: any = await Ride.findById(params.id).select('offeredTo status').lean()
    if (ride?.status === 'pending' && String(ride.offeredTo) === String(payload.id)) {
      await offerNext(params.id).catch(() => null)
    }

    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
