export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/rental  body.action:
//  'start'    { lat, lng }                  → mark start, set rentalStartedAt
//  'ping'     { lat, lng }                  → accumulate actualKm + actualHours (live)
//  'wait'     { isWaiting }                 → toggle halt
//  'addStop'  { address, lat, lng }
//  'extend'   { extraHours }                → increase packageHours
//  'end'      { lat, lng }                  → finalize, compute extras + finalFare
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const b = await req.json()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    const now = new Date()
    const action = b.action

    if (action === 'start') {
      ride.rentalStartedAt = now
      ride.rentalPhase = 'ongoing'
      ride.rentalLastLat = b.lat ?? ride.pickupLat
      ride.rentalLastLng = b.lng ?? ride.pickupLng
      ride.actualKm = 0
      ride.actualHours = 0
    } else if (action === 'ping') {
      // Accumulate distance from last point (skip while waiting)
      if (!ride.isWaiting && b.lat != null && b.lng != null && ride.rentalLastLat != null) {
        const d = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat: b.lat, lng: b.lng })
        if (d > 0.02) { // ignore GPS jitter < 20m
          ride.actualKm = +(ride.actualKm + d).toFixed(2)
          ride.rentalLastLat = b.lat
          ride.rentalLastLng = b.lng
        }
      }
      // Live elapsed hours from start
      if (ride.rentalStartedAt) {
        ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      // Flip to extra_time when over the package
      if (ride.actualHours > ride.packageHours || ride.actualKm > ride.packageKm) {
        if (ride.rentalPhase === 'ongoing') ride.rentalPhase = 'extra_time'
      }
    } else if (action === 'wait') {
      ride.isWaiting = !!b.isWaiting
      ride.rentalPhase = b.isWaiting ? 'paused' : (ride.actualHours > ride.packageHours ? 'extra_time' : 'ongoing')
      if (b.lat != null) { ride.rentalLastLat = b.lat; ride.rentalLastLng = b.lng } // reset anchor on resume
    } else if (action === 'addStop') {
      ride.rentalStops = ride.rentalStops || []
      ride.rentalStops.push({ address: b.address, lat: b.lat, lng: b.lng, at: now })
    } else if (action === 'extend') {
      ride.packageHours = (ride.packageHours || 0) + (b.extraHours || 0)
      // proportionally bump included km
      const perHrKm = ride.packageHours > 0 ? (ride.packageKm / ride.packageHours) : 0
      ride.packageKm = Math.round(perHrKm * ride.packageHours)
      if (ride.actualHours <= ride.packageHours) ride.rentalPhase = 'ongoing'
    } else if (action === 'end') {
      // Final distance/time
      if (b.lat != null && ride.rentalLastLat != null) {
        const d = distanceKm({ lat: ride.rentalLastLat, lng: ride.rentalLastLng }, { lat: b.lat, lng: b.lng })
        if (d > 0.02) ride.actualKm = +(ride.actualKm + d).toFixed(2)
      }
      if (ride.rentalStartedAt) {
        ride.actualHours = +(((now.getTime() - new Date(ride.rentalStartedAt).getTime()) / 3600000)).toFixed(2)
      }
      const extraHrs = Math.max(0, Math.ceil(ride.actualHours - ride.packageHours))
      const extraKms = Math.max(0, Math.ceil(ride.actualKm - ride.packageKm))
      ride.extraHoursCharge = extraHrs * (ride.extraHourRate || 0)
      ride.extraKmCharge = extraKms * (ride.extraKmRate || 0)
      const base = ride.fare || 0
      ride.finalFare = Math.round(base + ride.extraHoursCharge + ride.extraKmCharge + (ride.nightChargeRental || 0))
      ride.totalFare = ride.finalFare + (ride.tip || 0)
      ride.rentalPhase = 'completed'
      ride.rentalEndedAt = now
      ride.status = 'completed'
      ride.completedAt = now
    }

    await ride.save()
    return withCors({
      success: true,
      rental: {
        phase: ride.rentalPhase, isWaiting: ride.isWaiting,
        actualHours: ride.actualHours, actualKm: ride.actualKm,
        packageHours: ride.packageHours, packageKm: ride.packageKm,
        extraHoursCharge: ride.extraHoursCharge, extraKmCharge: ride.extraKmCharge,
        finalFare: ride.finalFare, status: ride.status,
        rentalStartedAt: ride.rentalStartedAt,
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
