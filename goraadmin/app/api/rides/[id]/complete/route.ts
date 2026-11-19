export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import Transaction from '@/models/Transaction'
import User from '@/models/User'
import { requireAuth, requireDriverAuth, isAdminPayload } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { distanceKm } from '@/lib/geo'

export async function OPTIONS() { return corsOptions() }

// POST → mark ride complete, split fare, deduct admin commission
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status === 'completed') return withCors({ error: 'Already completed' }, 400)

    // Settlement moves real money (commission, driver wallet, Transaction row),
    // so the caller must be a party to this ride. Both apps already send a
    // bearer token; this endpoint simply never checked it.
    const asDriver = requireDriverAuth(req) as any
    const asRider = requireAuth(req) as any
    const isDriver = !!asDriver?.id && !!ride.driverId && String(ride.driverId) === String(asDriver.id)
    const isRider = !!asRider?.id && !!ride.riderId && String(ride.riderId) === String(asRider.id)
    // Admin force-complete forwards here for stranded rides (see force-complete).
    const isAdminOverride = req.headers.get('x-admin-override') === '1' && isAdminPayload(asRider)
    if (!isDriver && !isRider && !isAdminOverride) return withCors({ error: 'Unauthorized' }, 401)

    const driver: any = await Driver.findById(ride.driverId)

    // Subscribed drivers pay a reduced/zero commission (Rapido-style pass)
    const subscribed = !!(driver && driver.subscriptionActive && driver.subscriptionExpiresAt
      && new Date(driver.subscriptionExpiresAt).getTime() > Date.now())

    // Commission % — subscription overrides the zone/booking commission
    let commissionPercent: number
    if (subscribed) {
      commissionPercent = driver.subscriptionCommissionPercent || 0
    } else {
      commissionPercent = ride.commissionPercent != null ? ride.commissionPercent : 20
      if (ride.commissionPercent == null) {
        const zone: any = await Zone.findById(ride.zoneId).lean()
        if (zone?.pricing) {
          const p = zone.pricing.find((x: any) => x.vehicleTypeName === ride.vehicleType && x.service === ride.service)
          if (p?.commissionPercent != null) commissionPercent = p.commissionPercent
        }
      }
    }

    // Services that bill extras at the end carry their own final amount.
    // Without this, a rental that ran 3 hours over settled on the booked base
    // fare and the platform's commission silently ignored every extra charge.
    const serviceFinal =
      ride.service === 'rental' ? (ride.finalFare || 0)
      : ride.service === 'hire_driver' ? (ride.hireFinalFare || 0)
      : ride.service === 'delivery' ? (ride.deliveryFinalFare || 0)
      : 0

    // Tip is 100% the driver's — commission applies only to the fare (+ multi-stop waiting charge)
    const waiting = ride.waitingChargeTotal || 0
    const tip = ride.tip || 0
    const billable = serviceFinal > 0 ? serviceFinal : (ride.fare || 0)
    const baseFare = billable + waiting             // commissionable amount (excludes tip)
    const fare = baseFare + tip                     // full amount (for records / response) — always the FULL fare, split or not
    ride.totalFare = fare
    // Split-fare co-riders already paid their share (and the driver was already
    // credited their cut of it) via /rides/{id}/split/pay, the moment each one
    // paid. Only the remainder is settled here, so the driver is never paid
    // commission-adjusted earnings on the same rupee twice.
    const splitCollected = Math.min(ride.splitCollected || 0, baseFare)
    const splitCommission = ride.splitCommission || 0
    const remainingBase = baseFare - splitCollected
    const commission = Math.round((remainingBase * commissionPercent) / 100)  // admin profit, on the not-yet-settled portion
    const driverEarning = (remainingBase - commission) + tip                  // driver keeps the full tip

    // Claim the ride before any money moves. The driver app retries End after
    // a 20 s timeout while the first request may still be running; reading the
    // status above is not enough, as both requests would pass it and settle
    // twice. Only the request that flips the status settles.
    const completedAt = new Date()
    const claim = await Ride.updateOne({ _id: ride._id, status: { $ne: 'completed' } }, { $set: { status: 'completed', completedAt } })
    if (claim.modifiedCount === 0) return withCors({ error: 'Already completed' }, 400)

    ride.status = 'completed'
    ride.completedAt = completedAt
    if (ride.service === 'outstation') {
      ride.outstationPhase = 'completed'
      // Billed at the fixed booked fare wherever it ends. One ended at the
      // pickup 38 s into a 223 km trip; the admin sees such trips flagged.
      const round = ride.tripType === 'round_trip'
      const endLat = round ? ride.pickupLat : ride.dropLat
      const endLng = round ? ride.pickupLng : ride.dropLng
      if (driver?.currentLat != null && driver?.currentLng != null && endLat != null && endLng != null) {
        const km = distanceKm({ lat: driver.currentLat, lng: driver.currentLng }, { lat: endLat, lng: endLng })
        if (km > 10) ride.endedAwayKm = Math.round(km)
      }
    }
    ride.paymentStatus = 'paid'
    ride.awaitingPayment = false
    ride.commissionPercent = commissionPercent
    // Stored as the ride's TOTAL, including whatever split co-riders already
    // settled through /rides/{id}/split/pay — otherwise a split ride would
    // under-report its commission and driver earning in finance dashboards.
    ride.commissionAmount = splitCommission + commission
    ride.driverEarning = (splitCollected - splitCommission) + driverEarning
    await ride.save()

    // Wallet changes are atomic increments: a read-modify-save here could
    // overwrite a top-up or another settlement that landed in between.
    let walletAfter: number | undefined
    if (driver) {
      const cash = ride.paymentMode === 'cash'
      // Cash: the rider paid the driver, who owes the commission.
      // Online/wallet: Gora received the money and credits the driver's earning.
      const delta = cash ? -commission : driverEarning
      const updated: any = await Driver.findByIdAndUpdate(driver._id,
        { $inc: { walletBalance: delta, totalRides: 1, totalEarnings: driverEarning } }, { new: true }).lean()
      walletAfter = updated?.walletBalance
      await Transaction.create(cash ? {
        driverId: driver._id, rideId: ride._id, type: 'commission',
        amount: -commission, paymentMode: 'cash',
        description: `Commission (${commissionPercent}%) on cash ride ₹${fare}`,
        balanceAfter: walletAfter,
      } : {
        driverId: driver._id, rideId: ride._id, type: 'ride_earning',
        amount: driverEarning, paymentMode: ride.paymentMode,
        description: `Earning on ${ride.paymentMode} ride ₹${fare} (admin took ₹${commission})`,
        balanceAfter: walletAfter,
      })
    }

    // ── Cash on delivery ──────────────────────────────────────────────────────
    // COD is the SENDER's money that happened to travel in the driver's pocket.
    // It is not revenue: no commission is taken on it, and it never touches the
    // `billable` figure above. It simply has to get from the driver to the
    // sender, which nothing did before — the driver collected it and kept it.
    //
    // Only a real handover moves it. On a return-to-sender the receiver never
    // paid, so codCollected is zero and this block does nothing.
    let codSettled = 0
    const cod = Math.max(0, Math.round(ride.codCollected || 0))
    if (ride.service === 'delivery' && cod > 0 && !ride.codSettledAt) {
      // Stamp first: /complete is reachable from both apps and is retried on a
      // flaky network, and paying the sender twice is unrecoverable.
      ride.codSettledAt = new Date()
      await ride.save()

      try {
        if (driver) {
          const updated: any = await Driver.findByIdAndUpdate(driver._id, { $inc: { walletBalance: -cod } }, { new: true }).lean()
          walletAfter = updated?.walletBalance
          await Transaction.create({
            driverId: driver._id, rideId: ride._id, type: 'cod_remittance',
            amount: -cod, paymentMode: 'cash',
            description: `COD ₹${cod} collected from receiver, owed to sender`,
            balanceAfter: walletAfter,
          })
        }
        if (ride.riderId) {
          await User.findByIdAndUpdate(ride.riderId, { $inc: { walletBalance: cod } })
        }
        codSettled = cod
      } catch (e) {
        // Leave codSettledAt stamped rather than risk a double payout on retry;
        // an unsettled balance is a reconciliation task, a double credit is not.
        console.error('[complete] COD settlement failed', e)
      }
    }

    return withCors({
      success: true,
      fare, commissionPercent,
      adminProfit: commission,
      driverEarning,
      driverWalletBalance: walletAfter ?? driver?.walletBalance ?? 0,
      codSettled,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
