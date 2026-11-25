export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import { requireDriverAuth } from '@/lib/auth'
import { getEtaFactor, crowKm, predictEtaMin, displayRoadKm } from '@/lib/eta'
import { driverIsBusy, driverEligibleFor, cachedGlobalSettings, kickDispatchSweeps, rideDueAt, rideIsOpenForDispatch, isAdvanceService, NO_DRIVER } from '@/lib/dispatch'
import { holdOf } from '@/lib/account-hold'
import { withCors, corsOptions } from '@/lib/cors'
import { sweepDueNotifications } from '@/lib/notifications'

export async function OPTIONS() { return corsOptions() }

// Hot path (every online driver, every 4 s): bounded scan, projected fields.
const FEED_SCAN_LIMIT = 60
const FEED_MAX = 20
const FEED_FIELDS = [
  'riderId', 'riderName', 'pickupAddress', 'dropAddress', 'pickupLat', 'pickupLng', 'dropLat', 'dropLng',
  'fare', 'tip', 'totalFare', 'distance', 'duration', 'vehicleType', 'paymentMode',
  'createdAt', 'stops', 'service', 'tripType', 'cityFrom', 'cityTo', 'departureAt', 'returnAt', 'scheduledAt',
  'numPassengers', 'packageHours', 'packageKm', 'hireTotalHours', 'transmission', 'hireStartAt', 'hireEndAt',
  'senderName', 'receiverName', 'itemType', 'weightKg', 'packageSize', 'isFragile', 'codAmount', 'parcelPhotos',
  'offeredTo', 'offerExpiresAt', 'rejectedBy', 'zoneId', 'preferFemaleDriver', 'preferences', 'status',
  'offerRound', 'dispatchActivatedAt', 'offeredHistory',
].join(' ')

// GET → pending ride requests this driver may accept (same zone + vehicle type, recent, not rejected)
// Also returns rider's profile photo so the driver app can show their face on incoming request.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    sweepDueNotifications()   // scheduled admin notifications that are due
    const driver: any = await Driver.findById(payload.id)
      .select('status isOnline accountHold faceVerificationRequired faceVerificationReason walletBalance selectedVehicleTypeName zoneId gender currentLat currentLng allowTaxi allowRental allowOutstation allowHireDriver allowDelivery acceptsRental acceptsOutstation acceptsHireDriver acceptsDelivery offerCooldownUntil')
      .lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Not approved / offline / on hold: no requests at all. (The feed used to
    // list rides to any driver who asked, approved or not.)
    if (driver.status !== 'approved') return withCors({ rides: [], notApproved: true })
    if (holdOf(driver).held) return withCors({ rides: [], hold: true })
    if (!driver.isOnline) return withCors({ rides: [], offline: true })

    // Ola-style block: if the driver's wallet is too far negative (unpaid cash
    // commission), stop sending ride requests until they recharge.
    const settings: any = await cachedGlobalSettings()
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

    const driverId = String(driver._id)

    // Move on lapsed offers / start scheduled rides due soon — throttled per
    // process, so 1 000 drivers polling every 4 s do not run it 250×/s.
    // Fire-and-forget: the sweep never delays this answer.
    kickDispatchSweeps()

    // A busy driver (on a trip, or with an accepted ride due within the hour —
    // see BUSY in lib/dispatch.ts) is shown no new requests, offered or open-pool.
    if (await driverIsBusy(driverId)) return withCors({ rides: [], busy: true })

    // Candidate query (cheap, indexed): this vehicle type, the services this
    // driver may take, this zone (or zone-less). driverEligibleFor below is the
    // exact rule accept applies.
    const baseFilter: any = { vehicleType: driver.selectedVehicleTypeName }
    const zoneOr = driver.zoneId ? { zoneId: { $in: [driver.zoneId, null] } } : {}
    const branches: any[] = []
    if (driver.allowTaxi !== false) branches.push({ ...baseFilter, ...zoneOr, service: { $nin: ['outstation', 'rental', 'hire_driver', 'delivery'] } })
    if (driver.acceptsOutstation && driver.allowOutstation !== false) branches.push({ ...baseFilter, ...zoneOr, service: 'outstation' })
    if (driver.acceptsRental && driver.allowRental !== false) branches.push({ ...baseFilter, ...zoneOr, service: 'rental' })
    if (driver.acceptsHireDriver && driver.allowHireDriver !== false) branches.push({ ...baseFilter, ...zoneOr, service: 'hire_driver' })
    if (driver.acceptsDelivery && driver.allowDelivery !== false) branches.push({ ...baseFilter, ...zoneOr, service: 'delivery' })
    if (branches.length === 0) return withCors({ rides: [] })

    // Fresh instant rides (created in the last 15 min), or scheduled ones whose
    // due time is recent or ahead (filtered to SCHEDULE_LEAD_MIN below).
    const now = new Date()
    const since = new Date(now.getTime() - 15 * 60 * 1000)
    const query: any = {
      status: 'pending',
      rejectedBy: { $ne: driverId },
      $and: [
        { $or: branches },
        { $or: [{ createdAt: { $gte: since } }, { scheduledAt: { $gte: since } }, { departureAt: { $gte: since } }, { hireStartAt: { $gte: since } }] },
      ],
    }

    let rides = await Ride.find(query).sort({ createdAt: -1 }).limit(FEED_SCAN_LIMIT).select(FEED_FIELDS).lean() as any[]

    // Freshness by DUE time: a plain taxi request is listed for 2 min after it
    // became due, other services for 15; scheduled ones only from
    // SCHEDULE_LEAD_MIN before they are due.
    rides = rides.filter((r: any) => {
      const due = rideDueAt(r).getTime()
      // Advance services stay listed for their whole no-driver grace.
      const fresh = isAdvanceService(r.service) ? Math.max(15, NO_DRIVER.ADVANCE_GRACE_MIN) : r.service === 'delivery' ? 15 : 2
      return due >= now.getTime() - fresh * 60_000 && rideIsOpenForDispatch(r, now)
    })

    // The ONE eligibility rule (same as accept): offered-to-someone-else,
    // zone, opt-in, cash on a negative wallet, female preference, ...
    const femalePool = new Map<string, boolean>()
    const keep: any[] = []
    for (const r of rides) {
      if (keep.length >= FEED_MAX) break
      if (!(await driverEligibleFor(driver, r, { settings, femalePool, now }))) keep.push(r)
    }
    rides = keep

    // ── Order the feed by ETA, not recency ──
    // Requests this driver can reach soonest come first, so the pings that
    // propagate first are the ones that minimise empty kilometres. Falls back
    // to recency when the driver has no location fix.
    const pickupEta = new Map<string, number>()
    const pickupKm = new Map<string, number>()
    if (driver.currentLat != null && driver.currentLng != null && rides.length > 0) {
      const from = { lat: driver.currentLat, lng: driver.currentLng }
      const factor = await getEtaFactor(from)
      for (const r of rides) {
        if (r.pickupLat == null || r.pickupLng == null) continue
        const crow = crowKm(from, { lat: r.pickupLat, lng: r.pickupLng })
        pickupKm.set(String(r._id), displayRoadKm(crow, factor))
        // Generous ceiling here on purpose: this only orders the driver's own
        // feed, so a far-away request should sort last rather than vanish.
        const min = predictEtaMin(crow, factor, { maxMin: 240 })
        if (min != null) pickupEta.set(String(r._id), min)
      }
      rides.sort((a: any, b: any) => {
        const ea = pickupEta.get(String(a._id))
        const eb = pickupEta.get(String(b._id))
        if (ea == null && eb == null) return new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
        if (ea == null) return 1
        if (eb == null) return -1
        return ea - eb
      })
    }

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
        // Names only before accept — no phone numbers (riderPhone /
        // senderPhone / receiverPhone come with /active once accepted).
        riderName: r.riderName,
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
        duration: r.duration,          // trip time pickup→drop (NOT arrival ETA)
        pickupEtaMin: pickupEta.get(String(r._id)) ?? null,  // this driver → pickup
        // Set when this ride was offered directly to this driver (countdown UI)
        offeredToMe: r.offeredTo ? String(r.offeredTo) === driverId : false,
        offerExpiresAt: r.offerExpiresAt ?? null,
        // Road-corrected driver→pickup km. The driver card previously fell back
        // to a client-side straight-line Geolocator.distanceBetween because the
        // server never sent this.
        pickupDistance: pickupKm.get(String(r._id)) ?? null,
        vehicleType: r.vehicleType,
        paymentMode: r.paymentMode,
        createdAt: r.createdAt,
        stops: r.stops,
        // Outstation extras (null for taxi rides — driver UI hides outstation chip)
        service: r.service,
        tripType: r.tripType,
        cityFrom: r.cityFrom,
        cityTo: r.cityTo,
        departureAt: r.departureAt,
        scheduledAt: r.scheduledAt,
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
        senderName: r.senderName,
        receiverName: r.receiverName,
        itemType: r.itemType, weightKg: r.weightKg,
        packageSize: r.packageSize, isFragile: r.isFragile,
        codAmount: r.codAmount, parcelPhotos: r.parcelPhotos,
      }
    })

    // Offers are paused after too many rejects (lib/dispatch REJECT_COOLDOWN); the open pool is still listed.
    const cooldown = driver.offerCooldownUntil && new Date(driver.offerCooldownUntil).getTime() > now.getTime() ? driver.offerCooldownUntil : null
    return withCors({ rides: result, ...(cooldown ? { offerCooldownUntil: cooldown } : {}) })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
