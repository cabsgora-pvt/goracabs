export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import Transaction from '@/models/Transaction'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST → mark ride complete, split fare, deduct admin commission
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status === 'completed') return withCors({ error: 'Already completed' }, 400)

    // Get commission % for this zone + vehicle + service (prefer value stored at booking)
    let commissionPercent = ride.commissionPercent != null ? ride.commissionPercent : 20
    if (ride.commissionPercent == null) {
      const zone: any = await Zone.findById(ride.zoneId).lean()
      if (zone?.pricing) {
        const p = zone.pricing.find((x: any) => x.vehicleTypeName === ride.vehicleType && x.service === ride.service)
        if (p?.commissionPercent != null) commissionPercent = p.commissionPercent
      }
    }

    // Use totalFare (fare + tip) as the base if present, plus any multi-stop waiting charge
    const waiting = ride.waitingChargeTotal || 0
    const fare = (ride.totalFare != null ? ride.totalFare : (ride.fare || 0)) + waiting
    if (waiting > 0) ride.totalFare = fare   // persist the waiting-inclusive total
    const commission = Math.round((fare * commissionPercent) / 100)  // admin profit
    const driverEarning = fare - commission

    ride.status = 'completed'
    ride.completedAt = new Date()
    ride.paymentStatus = 'paid'
    ride.commissionPercent = commissionPercent
    ride.commissionAmount = commission
    ride.driverEarning = driverEarning
    await ride.save()

    const driver: any = await Driver.findById(ride.driverId)
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

    return withCors({
      success: true,
      fare, commissionPercent,
      adminProfit: commission,
      driverEarning,
      driverWalletBalance: driver?.walletBalance ?? 0,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
