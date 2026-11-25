export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { offerNext, recordDriverEvent } from '@/lib/dispatch'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST → driver rejects a pending ride (stays pending for others).
// Counted on the driver (dispatchStats.rejects); REJECT_COOLDOWN.COUNT rejects
// in 10 min pause their OFFERS for 10 min (`offerCooldownUntil` in the answer).
// The open-pool feed stays visible.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)

    await connectDB()
    const driverId = String(payload.id)
    // Filtered on "not yet rejected": updateOne also bumps updatedAt, so
    // modifiedCount alone would count a repeat.
    const marked = await Ride.updateOne({ _id: params.id, status: 'pending', rejectedBy: { $ne: driverId } }, { $addToSet: { rejectedBy: driverId } })

    let cooldownUntil: Date | undefined
    // Count a reject once per ride (a double tap is not two rejects).
    if (marked.modifiedCount) cooldownUntil = (await recordDriverEvent(driverId, 'rejects')).cooldownUntil

    // If this driver was the one holding the offer, don't make the rider wait
    // out the countdown — escalate to the next candidate straight away. The
    // same atomic per-rung claim as the expiry sweep (offerNext matches the
    // offer this driver held), so a reject racing the sweep moves it once.
    const ride: any = await Ride.findById(params.id).select('offeredTo status').lean()
    if (ride?.status === 'pending' && String(ride.offeredTo) === driverId) {
      await offerNext(params.id, { offeredTo: driverId }).catch(() => null)
    }

    return withCors({ success: true, ...(cooldownUntil ? { offerCooldownUntil: cooldownUntil } : {}) })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
