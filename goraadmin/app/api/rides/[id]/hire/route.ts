export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/hire  body.action:
//  'start'  → mark hireStartedAt, phase ongoing
//  'ping'   → live actualHours (flip to overtime over booked hours)
//  'extend' { extraHours } → bump booked hours
//  'end'    → finalize: extra hours × perHour overtime, hireFinalFare
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const now = new Date()

    if (b.action === 'start') {
      ride.hireStartedAt = now
      ride.hirePhase = 'ongoing'
      ride.hireActualHours = 0
    } else if (b.action === 'ping') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      if (ride.hireActualHours > ride.hireTotalHours && ride.hirePhase === 'ongoing') ride.hirePhase = 'overtime'
    } else if (b.action === 'extend') {
      ride.hireTotalHours = (ride.hireTotalHours || 0) + (b.extraHours || 0)
      if (ride.hireActualHours <= ride.hireTotalHours) ride.hirePhase = 'ongoing'
    } else if (b.action === 'end') {
      if (ride.hireStartedAt) {
        ride.hireActualHours = +(((now.getTime() - new Date(ride.hireStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      const extra = Math.max(0, Math.ceil(ride.hireActualHours - ride.hireTotalHours))
      ride.hireExtraHours = extra
      ride.hireExtraCharge = extra * (ride.hirePerHour || 0)
      const base = ride.fare || 0
      ride.hireFinalFare = Math.round(base + ride.hireExtraCharge)
      ride.totalFare = ride.hireFinalFare + (ride.tip || 0)
      ride.hirePhase = 'completed'
      ride.hireEndAt = now
      ride.status = 'completed'
      ride.completedAt = now
    }

    await ride.save()
    return withCors({
      success: true,
      hire: {
        phase: ride.hirePhase, actualHours: ride.hireActualHours, totalHours: ride.hireTotalHours,
        extraHours: ride.hireExtraHours, extraCharge: ride.hireExtraCharge,
        finalFare: ride.hireFinalFare, status: ride.status, hireStartedAt: ride.hireStartedAt,
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
