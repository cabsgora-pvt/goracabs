export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireActiveDriver } from '@/lib/auth'
import { crowKm, getEtaFactor, predictEtaMin, ETA_CONFIG } from '@/lib/eta'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync } from '@/lib/push'
import { driverIsBusy, driverEligibleFor, cachedGlobalSettings, acquireAcceptLease, releaseAcceptLease, recordDriverEvent } from '@/lib/dispatch'
import { driverSafeRide, newShareToken } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

// POST → driver accepts a pending ride
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    // A blocked / deleted account or a revoked session takes no rides.
    const act = await requireActiveDriver(req)
    if (!act.ok) return withCors({ error: act.error, code: act.code }, act.status)
    const payload = act.payload

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    const pre: any = await Ride.findById(params.id).lean()
    if (!pre) return withCors({ error: 'Ride not found' }, 404)

    // Already this driver's — a repeat of an accept whose answer was lost
    // (the app gives up after 20 s while the server still finishes).
    if (String(pre.driverId || '') === String(driver._id) && ['accepted', 'arrived', 'ongoing'].includes(pre.status)) {
      return withCors({ success: true, ride: driverSafeRide(pre), repeated: true })
    }
    if (pre.status !== 'pending') return withCors({ error: 'Ride already taken', code: 'RIDE_TAKEN' }, 409)

    // ONE rule shared with the pending feed (lib/dispatch driverEligibleFor):
    // approved, online, not held / face-locked, wallet, vehicle type, service
    // allowed + opted in, zone, not declined, not offered exclusively to
    // someone else, scheduled ride open, female-driver preference.
    const settings = await cachedGlobalSettings()
    const no = await driverEligibleFor(driver, pre, { settings })
    if (no) {
      const { status, ...body } = no
      return withCors(body, status)
    }

    // One accept at a time per driver (a short lease on the driver document),
    // so the busy check and the claim below cannot interleave with the same
    // driver's accept of another ride. A second tap waits for the first.
    const lease = await acquireAcceptLease(String(driver._id))
    if (!lease) return withCors({ error: 'Another accept is in progress. Please try again.', code: 'ACCEPT_IN_PROGRESS' }, 409)
    let ride: any
    try {
      // A busy driver (see BUSY in lib/dispatch.ts) takes no other ride. The feed hides requests from
      // a busy driver; this stops one accepted from a stale screen or by id.
      if (await driverIsBusy(String(driver._id), params.id)) {
        return withCors({ error: 'Finish your current ride before accepting another', code: 'DRIVER_BUSY' }, 409)
      }

      // Atomic claim: only succeeds if still pending, for the vehicle type the
      // rider booked, not declined by this driver, and not held by someone
      // else's live offer — re-checked here so a race with the offer ladder
      // cannot slip through between the read above and this write.
      const now = new Date()
      ride = await Ride.findOneAndUpdate(
        {
          _id: params.id, status: 'pending', vehicleType: driver.selectedVehicleTypeName,
          rejectedBy: { $ne: String(driver._id) },
          $or: [{ offeredTo: null }, { offeredTo: driver._id }, { offerExpiresAt: null }, { offerExpiresAt: { $lte: now } }],
        },
        {
          $set: {
            status: 'accepted',
            driverId: driver._id,
            driverName: driver.name,
            driverPhone: driver.phone,
            acceptedAt: now,
          },
        },
        { new: true }
      )

      if (!ride) {
        const exists: any = await Ride.findById(params.id).lean()
        if (!exists) return withCors({ error: 'Ride not found' }, 404)
        if (String(exists.driverId || '') === String(driver._id) && ['accepted', 'arrived', 'ongoing'].includes(exists.status)) {
          return withCors({ success: true, ride: driverSafeRide(exists), repeated: true })
        }
        return withCors({ error: 'Ride already taken', code: 'RIDE_TAKEN' }, 409)
      }

      // Backstop for the double-acceptance race (e.g. a lease that expired
      // mid-request): with this claim in, the driver must have no OTHER active
      // ride due now. If they do, this claim is undone.
      if (await driverIsBusy(String(driver._id), String(ride._id))) {
        await Ride.updateOne(
          { _id: ride._id, driverId: driver._id, status: 'accepted' },
          { $set: { status: 'pending', driverId: null, driverName: null, driverPhone: null }, $unset: { acceptedAt: 1 } },
        )
        return withCors({ error: 'Finish your current ride before accepting another', code: 'DRIVER_BUSY' }, 409)
      }
    } finally {
      await releaseAcceptLease(String(driver._id), lease)
    }

    if (ride.service === 'outstation') {
      await Ride.updateOne({ _id: ride._id }, { $set: { outstationPhase: 'driver_arriving' } }).catch(() => {})
    }
    // The rider's live-tracking share link (GET /rides/track/{shareToken}),
    // unless they already asked for one while searching.
    await Ride.updateOne({ _id: ride._id, shareToken: null }, { $set: { shareToken: newShareToken() } }).catch(() => {})
    recordDriverEvent(driver._id, 'accepts').catch(() => {})

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

    // The pickup and drop OTPs are the rider's to read out; GET /rides/:id
    // withholds them from drivers, so this must too.
    return withCors({ success: true, ride: driverSafeRide(ride.toObject ? ride.toObject() : ride), predictedEtaMin })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
