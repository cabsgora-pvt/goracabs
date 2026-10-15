export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import Transaction from '@/models/Transaction'
import User from '@/models/User'
import { requireAuth, requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

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
    const isAdminOverride = req.headers.get('x-admin-override') === '1' && !!asRider?.id
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

    ride.status = 'completed'
    ride.completedAt = new Date()
    ride.paymentStatus = 'paid'
    ride.awaitingPayment = false
    ride.commissionPercent = commissionPercent
    // Stored as the ride's TOTAL, including whatever split co-riders already
    // settled through /rides/{id}/split/pay — otherwise a split ride would
    // under-report its commission and driver earning in finance dashboards.
    ride.commissionAmount = splitCommission + commission
    ride.driverEarning = (splitCollected - splitCommission) + driverEarning
    await ride.save()

    if (driver) {
      driver.totalRides = (driver.totalRides || 0) + 1
      driver.totalEarnings = (driver.totalEarnings || 0) + driverEarning

      if (ride.paymentMode === 'cash') {
        // Rider paid driver directly → driver owes commission → deduct from wallet
        driver.walletBalance = (driver.walletBalance || 0) - commission
        await Transaction.create({
          driverId: driver._id, rideId: ride._id, type: 'commission',
          amount: -commission, paymentMode: 'cash',
          description: `Commission (${commissionPercent}%) on cash ride ₹${fare}`,
          balanceAfter: driver.walletBalance,
        })
      } else {
        // Online/wallet → admin received money → credit driver earning
        driver.walletBalance = (driver.walletBalance || 0) + driverEarning
        await Transaction.create({
          driverId: driver._id, rideId: ride._id, type: 'ride_earning',
          amount: driverEarning, paymentMode: ride.paymentMode,
          description: `Earning on ${ride.paymentMode} ride ₹${fare} (admin took ₹${commission})`,
          balanceAfter: driver.walletBalance,
        })
      }
      await driver.save()
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
          driver.walletBalance = (driver.walletBalance || 0) - cod
          await Transaction.create({
            driverId: driver._id, rideId: ride._id, type: 'cod_remittance',
            amount: -cod, paymentMode: 'cash',
            description: `COD ₹${cod} collected from receiver, owed to sender`,
            balanceAfter: driver.walletBalance,
          })
          await driver.save()
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
      driverWalletBalance: driver?.walletBalance ?? 0,
      codSettled,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
