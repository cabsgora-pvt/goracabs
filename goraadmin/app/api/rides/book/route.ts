export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Zone from '@/models/Zone'
import { distanceKm, pointInPolygon } from '@/lib/geo'
// NB: local `roadDistanceKm` below is the trip distance — do not import the
// eta.ts helper of the same name into this file.
import { availableDriverFilter, getEtaFactor, rankCandidates, refineCandidatesWithTraffic, MATRIX_REFINE, ETA_CONFIG } from '@/lib/eta'
import { offerNext, withoutBusyDrivers, busyDriverIds } from '@/lib/dispatch'
import { chargedAtBooking, linkPrepayment } from '@/lib/prepay'
import { quoteRental, type RentalQuote } from '@/lib/rental-pricing'
import { evaluatePromo, consumePromo, type PromoResult } from '@/lib/promo'
import { verifyQuote, quoteCell, ENFORCE_QUOTES } from '@/lib/quote'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// Rider app builds before 1.2.2 send the picked wall-clock time with no zone
// ("2026-10-28T17:15:00.000"), which new Date() reads as UTC: a 5:15 PM IST
// hire was stored as 10:45 PM IST, and a rental's night charge was judged
// 5½ hours late. A zone-less time is the rider's IST wall clock.
function clientTime(v: unknown): Date | undefined {
  if (v == null || v === '') return undefined
  const s = String(v)
  const zoned = /(Z|[+-]\d{2}:?\d{2})$/i.test(s) || !s.includes('T')
  const d = new Date(zoned ? s : s + '+05:30')
  return isNaN(d.getTime()) ? undefined : d
}

// Helper: ask Google Directions for road distance + duration + polyline
async function fetchDirections(originLat: number, originLng: number, destLat: number, destLng: number) {
  try {
    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return null
    const url = `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${originLat},${originLng}` +
      `&destination=${destLat},${destLng}` +
      `&mode=driving&departure_time=now&traffic_model=best_guess` +
      `&key=${key}`
    const r = await fetch(url)
    const data = await r.json()
    if (data.status !== 'OK' || !data.routes?.length) return null
    const leg = data.routes[0].legs?.[0] || {}
    return {
      polyline: data.routes[0].overview_polyline?.points || '',
      distanceKm: +((leg.distance?.value || 0) / 1000).toFixed(2),
      durationMin: Math.round(((leg.duration_in_traffic?.value ?? leg.duration?.value) || 0) / 60),
    }
  } catch (e) {
    console.error('[Directions in book] failed', e)
    return null
  }
}

// POST booking → creates ride (status pending). Online matching drivers pick it up via polling.
export async function POST(req: NextRequest) {
  try {
    const b = await req.json()
    await connectDB()

    // Identify the rider from the auth token (falls back to body fields)
    const auth = requireAuth(req) as any
    let riderId = b.riderId
    let riderName = b.riderName
    let riderPhone = b.riderPhone
    if (auth?.id) {
      riderId = auth.id
      const user: any = await User.findById(auth.id).lean().catch(() => null)
      if (user) {
        riderName = riderName || user.name
        riderPhone = riderPhone || user.phone
      }
    }

    // Generate ride OTP (collection OTP for delivery)
    const otp = Math.floor(1000 + Math.random() * 9000).toString()
    // Delivery gets a second OTP for receiver handover
    const dropOtp = Math.floor(1000 + Math.random() * 9000).toString()

    const service = b.service || 'taxi'

    // A repeat of a booking already made: the app stops waiting after 20 s and
    // the rider taps Book again while the first request is still finishing.
    // Hand back that ride instead of creating a second one — but only for the
    // signed-in rider (the reply carries the pickup OTP), only when every part
    // of the booking matches (two parcels from home to two receivers are two
    // bookings), and never when this request carries its own prepayment: that
    // must be linked to a ride, not dropped.
    const sameTime = (a: unknown, stored: any) => {
      const x = clientTime(a)?.getTime() ?? null
      const y = stored ? new Date(stored).getTime() : null
      return x === y || (x !== null && y !== null && Math.abs(x - y) < 60_000)
    }
    const near = (aLat: any, aLng: any, bLat: any, bLng: any) =>
      (aLat == null && bLat == null) ||
      (aLat != null && bLat != null && distanceKm({ lat: aLat, lng: aLng }, { lat: bLat, lng: bLng }) < 0.1)
    if (auth?.id && b.pickupLat != null && b.pickupLng != null && !chargedAtBooking(service, b.paymentMode === 'cod' ? 'cash' : (b.paymentMode || 'cash'))) {
      const recent: any = await Ride.findOne({
        riderId: auth.id, service, vehicleType: b.vehicleType, status: 'pending',
        createdAt: { $gte: new Date(Date.now() - 2 * 60 * 1000) },
      }).sort({ createdAt: -1 }).lean()
      const same = recent
        && near(b.pickupLat, b.pickupLng, recent.pickupLat, recent.pickupLng)
        && near(b.dropLat ?? b.pickupLat, b.dropLng ?? b.pickupLng, recent.dropLat, recent.dropLng)
        && sameTime(b.scheduledAt, recent.scheduledAt)
        && sameTime(b.departureAt, recent.departureAt)
        && sameTime(b.hireStartAt, recent.hireStartAt)
        && String(b.receiverPhone || '') === String(recent.receiverPhone || '')
        && Number(b.packageHours || 0) === Number(recent.packageHours || 0)
        && String(b.tripType || 'one_way') === String(recent.tripType || 'one_way')
      if (same) {
        return withCors({
          success: true, duplicate: true,
          ride: {
            id: recent._id, otp: recent.otp, status: recent.status, fare: recent.fare, tip: recent.tip,
            totalFare: recent.totalFare, commissionPercent: recent.commissionPercent, distance: recent.distance,
            duration: recent.duration, routePolyline: recent.routePolyline, fareBreakdown: recent.fareBreakdown,
          },
        })
      }
    }

    // The zone the pickup is actually in, from its coordinates alone.
    let pickupZone: any = null
    if (b.pickupLat != null && b.pickupLng != null) {
      const zones = await Zone.find({ isActive: true }).lean() as any[]
      for (const z of zones) {
        if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: b.pickupLat, lng: b.pickupLng }, z.polygonPath)) {
          pickupZone = z; break
        }
      }
      if (!pickupZone) {
        let nd = Infinity
        for (const z of zones) {
          const d = distanceKm({ lat: b.pickupLat, lng: b.pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
          if (d < nd) { nd = d; pickupZone = z }
        }
        if (nd > 25) pickupZone = null
      }
    }

    // The ride's zone is where its pickup is. A zoneId in the body used to win:
    // no app sends one, but a crafted request could price a rental from a
    // cheaper zone's packages, or send the ride to another zone's drivers.
    const zone: any = pickupZone
    const zoneId = zone ? zone._id : undefined

    // Pricing row for this vehicle in this zone+service
    let pricingRow: any = null
    let commissionPercent = 20
    if (zone?.pricing) {
      pricingRow = zone.pricing.find((x: any) => x.vehicleTypeName === b.vehicleType && x.service === service)
      if (pricingRow?.commissionPercent != null) commissionPercent = pricingRow.commissionPercent
    }

    // Ask Google for actual road distance + duration + polyline (fallback to client-sent values)
    let routePolyline = ''
    let roadDistanceKm = b.distance
    let roadDurationMin = b.duration
    // Skip the (billed) Directions call when there is no real drop — rental
    // sends dropLat/dropLng equal to pickup, so this was one wasted Google
    // request per rental booking that only ever produced distance ≈ 0.
    const hasRealDrop = b.pickupLat != null && b.pickupLng != null
      && b.dropLat != null && b.dropLng != null
      && !(Math.abs(b.dropLat - b.pickupLat) < 1e-6 && Math.abs(b.dropLng - b.pickupLng) < 1e-6)
    if (hasRealDrop) {
      const dir = await fetchDirections(b.pickupLat, b.pickupLng, b.dropLat, b.dropLng)
      if (dir) {
        routePolyline = dir.polyline
        roadDistanceKm = dir.distanceKm
        roadDurationMin = dir.durationMin
      }
    }

    // Compute fare from pricing row + road distance/duration
    let computedFare = b.fare || 0
    let breakdown: any = null
    if (pricingRow && roadDistanceKm != null && roadDurationMin != null) {
      const base = pricingRow.baseFare || 0
      const perKm = pricingRow.perKm || 0
      const perMin = pricingRow.perMin || 0
      const minFare = pricingRow.minFare || 0
      const distanceCharge = +(roadDistanceKm * perKm).toFixed(2)
      const timeCharge = +(roadDurationMin * perMin).toFixed(2)
      let subtotal = +(base + distanceCharge + timeCharge).toFixed(2)
      if (subtotal < minFare) subtotal = minFare
      const surge = 0  // surge multiplier hook (set when surge feature is wired)
      const tax = 0    // tax hook
      const total = +(subtotal + surge + tax).toFixed(2)
      const commission = +((total * commissionPercent) / 100).toFixed(2)
      breakdown = { base, perKm, perMin, minFare, distanceKm: roadDistanceKm, durationMin: roadDurationMin, distanceCharge, timeCharge, subtotal, surge, tax, commission }
      // Only override the client-sent fare when the client didn't send one (server is the source of truth going forward)
      if (!b.fare) computedFare = total
    }

    // ── Rental: price on the server, never from the request body ──
    // zone.pricing never holds rental rows, so the generic block above always
    // left the client's fare standing. Everything money-related for a rental is
    // recomputed here from the zone's configured packages.
    let rentalQuote: RentalQuote | null = null
    let promo: PromoResult | null = null
    if (service === 'rental') {
      const startAt = clientTime(b.departureAt) ?? new Date()
      rentalQuote = quoteRental({
        zone,
        vehicleType: b.vehicleType,
        hours: b.packageHours,
        startAt,
      })
      if (!rentalQuote) {
        return withCors({ error: 'No rental package available for this vehicle in this zone' }, 400)
      }
      computedFare = rentalQuote.fare
      commissionPercent = rentalQuote.commissionPercent

      // Coupons are now validated server-side against PromoCode (expiry, usage
      // cap, minimum fare) instead of trusting the client's own subtraction.
      promo = await evaluatePromo(b.couponCode, computedFare, pickupZone?._id)  // where the pickup is, never a zone the client names
      if (promo.discount > 0) computedFare = Math.max(0, computedFare - promo.discount)
    }

    // ── Non-rental services: the fare must be one WE signed ──
    // book cannot recompute outstation/hire/delivery pricing without duplicating
    // those formulas (and risking drift from the quoted price), so /fare/estimate
    // signs the fare it just produced and we verify it here.
    let quoteWarning: string | null = null
    if (service !== 'rental') {
      const check = verifyQuote(b.quoteToken, {
        service,
        vehicleType: b.vehicleType,
        // Hire is priced on hours alone, so /fare/estimate signs it without a
        // drop; the rider app still sends one (pickup again), so ignore it here.
        cell: service === 'hire_driver'
          ? quoteCell(b.pickupLat, b.pickupLng, null, null)
          : quoteCell(b.pickupLat, b.pickupLng, b.dropLat, b.dropLng),
      })
      if (check.ok) {
        computedFare = check.fare        // authoritative: exactly what was quoted
      } else if (ENFORCE_QUOTES) {
        return withCors({ error: `Fare quote rejected: ${check.reason}. Please refresh and try again.` }, 400)
      } else {
        // Rollout grace: older app builds do not send a token yet. Log loudly so
        // the gap is visible, then flip ENFORCE_QUOTE_TOKEN=1 once they update.
        quoteWarning = check.reason
        console.warn('[book] unsigned fare accepted', { service, vehicleType: b.vehicleType, fare: computedFare, reason: check.reason })
      }
    }

    const fare = computedFare
    // The per-km breakdown above is the taxi formula. Every other service is
    // priced elsewhere (signed quote, rental packages), so on an outstation ride
    // it stored ₹2535 / commission 507 beside a fare of ₹3450. Keep only what is
    // true for those: the route measured and the fare actually booked.
    if (breakdown && service !== 'taxi') {
      breakdown = {
        distanceKm: breakdown.distanceKm, durationMin: breakdown.durationMin,
        subtotal: fare, surge: 0, tax: 0,
        commission: +((fare * commissionPercent) / 100).toFixed(2),
      }
    }
    const tip = b.tip || 0
    const totalFare = fare + tip

    // Installed builds of the rider app send 'cod' for a parcel with cash on
    // delivery switched on. The Ride schema only accepts cash / wallet / online,
    // so every such booking failed validation and was never created. With COD on,
    // the app has always collected the fare as cash, so that is what it is.
    const paymentMode = b.paymentMode === 'cod' ? 'cash' : (b.paymentMode || 'cash')

    const ride = await Ride.create({
      riderId, riderName, riderPhone,
      pickupAddress: b.pickupAddress, dropAddress: b.dropAddress,
      pickupLat: b.pickupLat, pickupLng: b.pickupLng,
      dropLat: b.dropLat, dropLng: b.dropLng,
      service, vehicleType: b.vehicleType,
      fare, tip, totalFare, commissionPercent,
      distance: roadDistanceKm, duration: roadDurationMin,
      routePolyline,
      fareBreakdown: breakdown,
      paymentMode,
      zoneId, otp, status: 'pending',
      preferFemaleDriver: !!b.preferFemaleDriver,
      // Outstation-only fields (silently ignored for other services)
      tripType: b.tripType || 'one_way',
      cityFrom: b.cityFrom,
      cityTo: b.cityTo,
      departureAt: clientTime(b.departureAt),
      returnAt: clientTime(b.returnAt),
      numPassengers: b.numPassengers || 1,
      multiStops: Array.isArray(b.multiStops) ? b.multiStops : [],
      nightHaltCharge: b.nightHaltCharge || 0,
      emptyReturnCharge: b.emptyReturnCharge || 0,
      // Rental-only fields — all server-derived, request body is not trusted
      packageHours: rentalQuote ? rentalQuote.hours : 0,
      packageKm: rentalQuote ? rentalQuote.km : 0,
      extraHourRate: rentalQuote ? rentalQuote.extraHourRate : 0,
      extraKmRate: rentalQuote ? rentalQuote.extraKmRate : 0,
      nightChargeRental: rentalQuote ? rentalQuote.nightCharge : 0,
      rentalPhase: service === 'rental' ? 'pending' : undefined,
      // Hire-a-driver fields
      hireStartAt: clientTime(b.hireStartAt),
      hireEndAt: clientTime(b.hireEndAt),
      hireTotalHours: b.hireTotalHours || 0,
      hirePerHour: b.hirePerHour || 0,
      transmission: b.transmission || '',
      // Multi-stop (in-city)
      stops: Array.isArray(b.stops) && b.stops.length ? b.stops.map((s: any) => ({ address: s.address, lat: s.lat, lng: s.lng })) : undefined,
      // Delivery fields
      senderName: b.senderName, senderPhone: b.senderPhone,
      receiverName: b.receiverName, receiverPhone: b.receiverPhone,
      itemType: b.itemType, weightKg: b.weightKg || 0,
      parcelPhotos: Array.isArray(b.parcelPhotos) ? b.parcelPhotos : [],
      dropOtp: service === 'delivery' ? dropOtp : undefined,
      deliveryPhase: service === 'delivery' ? 'pending' : undefined,
      packageSize: b.packageSize || '',
      isFragile: !!b.isFragile,
      itemValue: b.itemValue || 0,
      codAmount: b.codAmount || 0,
      // A rental booked for a future departureAt is a SCHEDULED ride. It used to
      // land only in `departureAt` (an outstation field), leaving scheduledAt
      // unset — so a rental booked for next week was broadcast to drivers
      // immediately and then aged out of the feed after 15 minutes.
      scheduledAt: clientTime(b.scheduledAt)
        ?? (service === 'rental' && (clientTime(b.departureAt)?.getTime() ?? 0) > Date.now() + 60_000
            ? clientTime(b.departureAt)
            : undefined),
      deliveryStops: Array.isArray(b.deliveryStops) && b.deliveryStops.length ? b.deliveryStops : undefined,
      // Charged before booking (outstation wallet/online): presumed NOT yet tied
      // to a verified payment until linkPrepayment below proves otherwise. Kept
      // true on any failure, so the ride is never auto-closed without a refund.
      prepaidUnlinked: chargedAtBooking(service, paymentMode),
    })

    // Tie an upfront payment to this ride from a server-verified source, so a
    // ride the system closes for "No driver found" can give it back.
    // Authenticated rider only: the debit or order must be provably theirs.
    await linkPrepayment(ride, auth?.id, b)

    // Record the redemption only once the ride actually exists.
    if (promo?.applied) await consumePromo(promo.code)

    // Offer the ride to the best-ranked captain and push them, instead of
    // listing it to everyone at once. Best-effort: a dispatch failure must
    // never fail the booking — the ride simply stays in the open pool.
    let offeredDriverId: string | null = null
    try { offeredDriverId = await offerNext(String(ride._id)) } catch (e) { console.error('[book] offer failed', e) }

    // ── Pick the best driver by ETA, not by raw crow-flies distance ──
    // Fresh location + not already on a ride + inside a sane pickup radius.
    let nearest: any = null
    let nearestKm: number | null = null
    let nearestEtaMin: number | null = null

    if (b.pickupLat != null && b.pickupLng != null) {
      const pickup = { lat: b.pickupLat, lng: b.pickupLng }
      const [factor, drivers] = await Promise.all([
        getEtaFactor(pickup),
        Driver.find(availableDriverFilter({
          ...(zoneId ? { zoneId: String(zoneId) } : {}),
          selectedVehicleTypeName: b.vehicleType,
          // Matches offerNext()'s own female-first-then-everyone fallback, so
          // this preview ETA doesn't promise a driver the real dispatch isn't
          // actually about to look for.
          ...(b.preferFemaleDriver ? { gender: 'female' } : {}),
        })).lean() as Promise<any[]>,
      ])

      const byId = new Map<string, any>((drivers as any[]).map(d => [String(d._id), d]))
      const busy = await busyDriverIds((drivers as any[]).map(d => String(d._id)))
      // Same rule as the dispatch ladder: a driver with an active ride is not a
      // candidate at all, so this preview never names one the ladder won't offer.
      let ranked = rankCandidates(withoutBusyDrivers(drivers, busy), pickup, factor).slice(0, ETA_CONFIG.CANDIDATE_POOL)

      if (ranked.length) {
        // Same traffic refinement the real dispatch ladder uses, via the shared
        // helper rather than a second hand-rolled copy of the matrix call. The
        // cached leg from offerNext() above is almost always reused here, so
        // this costs nothing extra when the flag is on.
        if (MATRIX_REFINE.DISPATCH) {
          ranked = await refineCandidatesWithTraffic(ranked, pickup)
        }

        const best = ranked[0]
        nearest = byId.get(best.id) ?? null
        nearestKm = best.km
        nearestEtaMin = best.etaMin
      }
    }

    return withCors({
      success: true,
      ride: {
        id: ride._id, otp, status: 'pending', fare, tip, totalFare, commissionPercent,
        distance: roadDistanceKm, duration: roadDurationMin, routePolyline, fareBreakdown: breakdown,
      },
      // Lets the app show "coupon expired" rather than silently charging full price.
      promo: promo && promo.code ? promo : null,
      rentalPackage: rentalQuote,
      quoteWarning,
      driverFound: !!nearest,
      offeredDriverId,
      driver: nearest
        ? { id: nearest._id, name: nearest.name, phone: nearest.phone, distanceKm: nearestKm, etaMin: nearestEtaMin }
        : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
