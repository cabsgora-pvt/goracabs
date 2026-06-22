export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import VehicleType from '@/models/VehicleType'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

const FREE_WAIT_MIN = 5 // free waiting minutes per stop

// POST /api/rides/{id}/stop  body.action:
//  'reached' { index }  → driver reached stop[index]; start its wait timer
//  'resume'  { index }  → driver resumes; add wait charge for that stop; advance currentStopIndex
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (!ride.stops || !ride.stops.length) return withCors({ error: 'No stops on this ride' }, 400)

    const idx = b.index ?? ride.currentStopIndex ?? 0
    const stop = ride.stops[idx]
    if (!stop) return withCors({ error: 'Invalid stop index' }, 400)

    const now = new Date()

    if (b.action === 'reached') {
      stop.reachedAt = now
      stop.waitStartedAt = now
      ride.isWaitingAtStop = true
    } else if (b.action === 'resume') {
      // Compute waited minutes beyond free wait → charge
      if (stop.waitStartedAt) {
        const mins = (now.getTime() - new Date(stop.waitStartedAt).getTime()) / 60000
        stop.waitMinutes = +mins.toFixed(1)
        const billable = Math.max(0, Math.ceil(mins - FREE_WAIT_MIN))
        // waiting rate from the vehicle type
        let rate = 1
        const vt: any = await VehicleType.findOne({ name: ride.vehicleType }).select('waitingCharge').lean()
        if (vt?.waitingCharge != null) rate = vt.waitingCharge
        ride.waitingChargeTotal = +(ride.waitingChargeTotal + billable * rate).toFixed(2)
      }
      stop.done = true
      ride.isWaitingAtStop = false
      ride.currentStopIndex = idx + 1
    }

    ride.markModified('stops')
    await ride.save()
    return withCors({
      success: true,
      currentStopIndex: ride.currentStopIndex,
      isWaitingAtStop: ride.isWaitingAtStop,
      waitingChargeTotal: ride.waitingChargeTotal,
      freeWaitMin: FREE_WAIT_MIN,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
