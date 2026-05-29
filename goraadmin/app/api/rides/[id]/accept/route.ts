export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST → driver accepts a pending ride
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Atomic claim: only succeeds if still pending
    const ride: any = await Ride.findOneAndUpdate(
      { _id: params.id, status: 'pending' },
      {
        $set: {
          status: 'accepted',
          driverId: driver._id,
          driverName: driver.name,
          driverPhone: driver.phone,
          acceptedAt: new Date(),
        },
      },
      { new: true }
    )

    if (!ride) {
      const exists = await Ride.findById(params.id).lean()
      if (!exists) return withCors({ error: 'Ride not found' }, 404)
      return withCors({ error: 'Ride already taken' }, 409)
    }

    return withCors({ success: true, ride })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
