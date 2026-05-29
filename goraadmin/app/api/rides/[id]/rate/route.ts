export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST { by:'rider'|'driver', rating, review }
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const { by, rating, review } = await req.json()
    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    if (by === 'rider') {
      // Rider rates the driver
      ride.driverRating = rating
      ride.driverReview = review || ''
      await ride.save()

      // Recompute driver's average rating from rated rides
      if (ride.driverId) {
        const rated = await Ride.find({ driverId: ride.driverId, driverRating: { $ne: null } })
          .select('driverRating').lean() as any[]
        if (rated.length) {
          const avg = rated.reduce((s, r) => s + (r.driverRating || 0), 0) / rated.length
          await Driver.findByIdAndUpdate(ride.driverId, { rating: +avg.toFixed(2) })
        }
      }
    } else {
      // Driver rates the rider
      ride.riderRating = rating
      ride.riderReview = review || ''
      await ride.save()
    }

    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
