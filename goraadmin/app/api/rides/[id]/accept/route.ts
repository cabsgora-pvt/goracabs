export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import Settings from '@/models/Settings'
import { crowKm, getEtaFactor, predictEtaMin, ETA_CONFIG } from '@/lib/eta'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync } from '@/lib/push'

export async function OPTIONS() { return corsOptions() }

// POST → driver accepts a pending ride
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Same wallet block the pending feed applies — the feed only hides rides,
    // so without this a blocked driver could still accept one by id.
    const settings: any = await Settings.findOne({ key: 'global' }).lean()
    const da = settings?.driverApp || {}
    const maxNeg = Math.abs(Number(da.maxNegativeWallet ?? 500))
    if (da.walletBlockEnabled !== false && (driver.walletBalance || 0) < -maxNeg) {
      return withCors({ error: `Low wallet balance (₹${Math.round(driver.walletBalance || 0)}). Please recharge to accept rides.` }, 403)
    }

    // Atomic claim: only succeeds if still pending, and only for the vehicle
    // type the rider booked (the feed is filtered the same way).
    const ride: any = await Ride.findOneAndUpdate(
      { _id: params.id, status: 'pending', vehicleType: driver.selectedVehicleTypeName },
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
      if ((exists as any).vehicleType !== driver.selectedVehicleTypeName) {
        return withCors({ error: 'This ride is for a different vehicle type' }, 403)
      }
      return withCors({ error: 'Ride already taken' }, 409)
    }

    // ── ETA telemetry ──
    // Record what we predicted so /arrived can measure the error. This is what
    // makes ETA accuracy observable at all, and it feeds the speed-profile
    // learner. Best-effort: never fail an accept because telemetry failed.
    let predictedEtaMin: number | null = null
    try {
      if (driver.currentLat != null && driver.currentLng != null && ride.pickupLat != null) {
        const pickup = { lat: ride.pickupLat, lng: ride.pickupLng }
        // Record the CROW distance, not a circuity-corrected one. /arrived
        // divides the real elapsed minutes by this to learn minutes-per-crow-km,
        // so the denominator has to be a measured quantity. The old code stored
        // crow x 1.4 and divided by that, which fed the circuity guess back into
        // the learned value and made the model chase its own error.
        const crow = crowKm({ lat: driver.currentLat, lng: driver.currentLng }, pickup)
        const factor = await getEtaFactor(pickup)
        // Same ceiling the quote side uses. These used to disagree (45 vs 120),
        // so an accepted ride could record a prediction the booking screen would
        // have refused to show.
        predictedEtaMin = predictEtaMin(crow, factor, { maxMin: ETA_CONFIG.MAX_ETA_MIN })
        await Ride.updateOne({ _id: ride._id }, {
          $set: {
            predictedEtaMin,
            pickupCrowKm: +crow.toFixed(3),
            etaMinPerKm: +factor.minPerKm.toFixed(3),
            etaFactorSource: factor.source,
            etaPredictedAt: new Date(),
          },
        })
      }
    } catch (e) {
      console.error('[accept] ETA telemetry failed', e)
    }

    // Tell the rider a captain is on the way. Their screen polls every 3 s, so
    // this is not the only path — but it is the one that works with the app
    // backgrounded, which polling never does.
    pushToUserAsync(ride.riderId, {
      title: 'Driver on the way',
      body: predictedEtaMin != null
        ? `${driver.name || 'Your captain'} arrives in about ${predictedEtaMin} min`
        : `${driver.name || 'Your captain'} has accepted your ride`,
      channelId: 'ride_updates',
      data: {
        type: 'ride_accepted',
        rideId: String(ride._id),
        ...(predictedEtaMin != null ? { etaMin: String(predictedEtaMin) } : {}),
      },
    })

    return withCors({ success: true, ride, predictedEtaMin })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
