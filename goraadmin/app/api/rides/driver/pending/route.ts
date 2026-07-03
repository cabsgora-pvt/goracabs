export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Settings from '@/models/Settings'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → pending ride requests this driver may accept (same zone + vehicle type, recent, not rejected)
// Also returns rider's profile photo so the driver app can show their face on incoming request.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Ola-style block: if the driver's wallet is too far negative (unpaid cash
    // commission), stop sending ride requests until they recharge.
    const settings: any = await Settings.findOne({ key: 'global' }).lean()
    const da = settings?.driverApp || {}
    const blockEnabled = da.walletBlockEnabled !== false
    const maxNeg = Math.abs(Number(da.maxNegativeWallet ?? 500))
    if (blockEnabled && (driver.walletBalance || 0) < -maxNeg) {
      return withCors({
        rides: [],
        walletBlocked: true,
        reason: `Low wallet balance (₹${Math.round(driver.walletBalance || 0)}). Please recharge to receive ride requests.`,
      })
    }

    const twoMinAgo = new Date(Date.now() - 2 * 60 * 1000)
    const driverId = String(driver._id)

    // Build a $or so drivers see in-city taxi rides PLUS opt-in services (outstation, rental).
    // Taxi/delivery/hire are always shown; outstation + rental require the driver to opt in.
    const baseFilter: any = {
      vehicleType: driver.selectedVehicleTypeName,
    }
    // Taxi branch covers everyday in-city rides (NOT opt-in services)
    const taxiBranch: any = { ...baseFilter, service: { $nin: ['outstation', 'rental', 'hire_driver', 'delivery'] } }
    if (driver.zoneId) taxiBranch.zoneId = driver.zoneId

    // Gate each service by the admin-set allow flag (default allowed)
    const branches: any[] = []
    if (driver.allowTaxi !== false) branches.push(taxiBranch)
    if (driver.acceptsOutstation && driver.allowOutstation !== false) branches.push({ ...baseFilter, service: 'outstation' })
    if (driver.acceptsRental && driver.allowRental !== false) branches.push({ ...baseFilter, service: 'rental' })
    if (driver.acceptsHireDriver && driver.allowHireDriver !== false) branches.push({ ...baseFilter, service: 'hire_driver' })
    if (driver.acceptsDelivery && driver.allowDelivery !== false) branches.push({ ...baseFilter, service: 'delivery' })
    if (branches.length === 0) return withCors({ rides: [] })

    const query: any = {
      status: 'pending',
      createdAt: { $gte: new Date(Date.now() - 15 * 60 * 1000) },
      rejectedBy: { $ne: driverId },
      $or: branches,
    }

    // Outstation + rental stay valid up to 15 min; plain taxi keeps the 2-min freshness window
    let rides = await Ride.find(query).sort({ createdAt: -1 }).lean() as any[]
    rides = rides.filter((r: any) => {
      if (['outstation', 'rental', 'hire_driver', 'delivery'].includes(r.service)) return true
      return new Date(r.createdAt) >= twoMinAgo
    })

    // Batch-load rider profile pics
    const riderIds = Array.from(new Set(rides.map((r: any) => String(r.riderId)).filter(Boolean)))
    const users = riderIds.length
      ? await User.find({ _id: { $in: riderIds } }).select('profilePicUrl rating').lean()
      : []
    const userMap = new Map<string, any>(users.map((u: any) => [String(u._id), u]))

    const result = rides.map((r: any) => {
      const u = r.riderId ? userMap.get(String(r.riderId)) : null
      return {
        id: r._id,
        riderName: r.riderName,
        riderPhone: r.riderPhone,
        riderProfilePicUrl: u?.profilePicUrl || '',
        riderRating: u?.rating ?? null,
        pickupAddress: r.pickupAddress,
        dropAddress: r.dropAddress,
        pickupLat: r.pickupLat, pickupLng: r.pickupLng,
        dropLat: r.dropLat, dropLng: r.dropLng,
        fare: r.fare,
        tip: r.tip,
        totalFare: r.totalFare,
        distance: r.distance,
        duration: r.duration,
        vehicleType: r.vehicleType,
        paymentMode: r.paymentMode,
        routePolyline: r.routePolyline,
        createdAt: r.createdAt,
        stops: r.stops,
        // Outstation extras (null for taxi rides — driver UI hides outstation chip)
        service: r.service,
        tripType: r.tripType,
        cityFrom: r.cityFrom,
        cityTo: r.cityTo,
        departureAt: r.departureAt,
        returnAt: r.returnAt,
        numPassengers: r.numPassengers,
        // Rental extras
        packageHours: r.packageHours,
        packageKm: r.packageKm,
        // Hire extras
        hireTotalHours: r.hireTotalHours,
        transmission: r.transmission,
        hireStartAt: r.hireStartAt,
        hireEndAt: r.hireEndAt,
        // Delivery extras
        senderName: r.senderName, senderPhone: r.senderPhone,
        receiverName: r.receiverName, receiverPhone: r.receiverPhone,
        itemType: r.itemType, weightKg: r.weightKg,
        packageSize: r.packageSize, isFragile: r.isFragile,
        codAmount: r.codAmount, parcelPhotos: r.parcelPhotos,
      }
    })

    return withCors({ rides: result })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
