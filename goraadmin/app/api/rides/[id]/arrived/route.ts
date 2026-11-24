export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireDriverAuth } from '@/lib/auth'
import { ETA_CONFIG } from '@/lib/eta'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync } from '@/lib/push'
import Driver from '@/models/Driver'
import { distanceKm } from '@/lib/geo'

const ARRIVE_MAX_KM = 1
const ARRIVE_FIX_FRESH_MS = 2 * 60 * 1000

export async function OPTIONS() { return corsOptions() }

// POST → driver arrived at pickup.
//
// Also closes the ETA feedback loop: compares the ETA promised at accept with
// the real acceptedAt → arrivedAt gap, and derives minutes-per-crow-km, which
// /api/cron/speed-profile aggregates into EtaProfile.
//
// Both terms of that ratio are measured. The previous version divided the
// PREDICTED road distance by the real time, so a wrong circuity assumption was
// laundered into the learned value and pushed later predictions further off.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const existing: any = await Ride.findById(params.id)
      .select('status driverId arrivedAt acceptedAt predictedEtaMin pickupCrowKm pickupLat pickupLng')
      .lean()
    if (!existing) return withCors({ error: 'Ride not found' }, 404)

    // Only the driver assigned to this ride may mark it arrived. This used to
    // accept any signed-in driver for any ride id.
    if (!existing.driverId || String(existing.driverId) !== String(payload.id)) {
      return withCors({ error: 'This ride is not assigned to you' }, 403)
    }

    // Idempotent. A driver app resumed mid-wait used to show the Arrived action
    // again, and a second call overwrote arrivedAt and recomputed pickup time
    // from acceptedAt to "now" — resetting the rider's waiting clock and feeding
    // an inflated sample into the ETA learner. A repeat is now a no-op.
    if (existing.status === 'arrived') {
      return withCors({
        success: true,
        alreadyArrived: true,
        waitingSec: existing.arrivedAt
          ? Math.max(0, Math.floor((Date.now() - new Date(existing.arrivedAt).getTime()) / 1000))
          : 0,
      })
    }

    // Only a ride that is on its way to pickup can arrive. Without this guard a
    // stray call moved an ongoing, or even completed, ride backwards to arrived.
    if (existing.status !== 'accepted') {
      return withCors({ error: `Cannot mark arrived from status '${existing.status}'` }, 409)
    }

    const arrivedAt = new Date()
    const update: any = { status: 'arrived', arrivedAt }

    // Must actually be at the pickup. With a fresh fix (< 2 min old) the driver
    // must be within ARRIVE_MAX_KM of it, else 409 TOO_FAR_FROM_PICKUP. With no
    // fresh fix (GPS off / stale) it is allowed but flagged on the ride:
    // arrivedUnverified, plus arrivedFarKm when the last known fix was > 1 km off.
    if (existing.pickupLat != null && existing.pickupLng != null) {
      const drv: any = await Driver.findById(payload.id).select('currentLat currentLng locationUpdatedAt').lean()
      const hasFix = drv?.currentLat != null && drv?.currentLng != null && !(drv.currentLat === 0 && drv.currentLng === 0)
      const km = hasFix ? distanceKm({ lat: drv.currentLat, lng: drv.currentLng }, { lat: existing.pickupLat, lng: existing.pickupLng }) : null
      const fresh = hasFix && drv.locationUpdatedAt && Date.now() - new Date(drv.locationUpdatedAt).getTime() < ARRIVE_FIX_FRESH_MS
      if (fresh && km != null && km > ARRIVE_MAX_KM) {
        return withCors({ error: `You are ${km.toFixed(1)} km from the pickup point`, code: 'TOO_FAR_FROM_PICKUP', distanceKm: +km.toFixed(2) }, 409)
      }
      if (!fresh) {
        update.arrivedUnverified = true
        if (km != null && km > ARRIVE_MAX_KM) update.arrivedFarKm = +km.toFixed(2)
      }
    }

    if (existing.acceptedAt) {
      const actualMin = (arrivedAt.getTime() - new Date(existing.acceptedAt).getTime()) / 60000
      // Discard nonsense samples (clock skew, a driver who forgot to tap
      // "arrived" for an hour) so they cannot poison the learned profile.
      if (actualMin > 0.5 && actualMin < 120) {
        update.actualPickupMin = +actualMin.toFixed(2)
        if (existing.predictedEtaMin != null) {
          update.etaErrorMin = +(actualMin - existing.predictedEtaMin).toFixed(2)
        }
        // ── The learning signal ──
        // Minutes per CROW km, from two measured quantities: the straight-line
        // distance recorded at accept, and the real elapsed time. Detour and
        // congestion are both folded in, so no circuity constant is assumed and
        // none can feed back into the estimate.
        //
        // The fixed pickup overhead is removed first: it does not scale with
        // distance, so leaving it in would inflate the per-km rate learned from
        // short pickups and deflate it for long ones.
        const crow = existing.pickupCrowKm
        if (crow != null && crow >= 0.2) {
          const travelMin = actualMin - ETA_CONFIG.PICKUP_OVERHEAD_MIN
          if (travelMin > 0) {
            const minPerKm = travelMin / crow
            if (minPerKm >= ETA_CONFIG.MIN_MIN_PER_KM && minPerKm <= ETA_CONFIG.MAX_MIN_PER_KM) {
              update.observedMinPerKm = +minPerKm.toFixed(3)
            }
          }
        }
      }
    }

    // Atomic on status: if two arrive calls race (a double swipe, a retry on a
    // flaky network), exactly one performs the transition and records telemetry.
    const ride: any = await Ride.findOneAndUpdate(
      { _id: params.id, driverId: existing.driverId, status: 'accepted' },
      { $set: update },
      { new: true },
    )
    if (!ride) {
      // Lost the race to a concurrent call that already moved it to arrived.
      return withCors({ success: true, alreadyArrived: true, waitingSec: 0 })
    }

    // The one notification a rider genuinely needs to see with the app closed:
    // the captain is outside and the waiting clock is about to start.
    pushToUserAsync(ride.riderId, {
      title: 'Your driver has arrived',
      body: ride.driverName
        ? `${ride.driverName} is waiting at your pickup point`
        : 'Your captain is waiting at the pickup point',
      channelId: 'ride_updates',
      data: { type: 'driver_arrived', rideId: String(ride._id), otp: String(ride.otp || '') },
    })

    return withCors({
      success: true,
      waitingSec: 0,
      eta: {
        predictedMin: ride.predictedEtaMin ?? null,
        actualMin: ride.actualPickupMin ?? null,
        errorMin: ride.etaErrorMin ?? null,
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
