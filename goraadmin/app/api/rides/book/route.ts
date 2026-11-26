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
import { holdOf, holdMessage } from '@/lib/account-hold'
import RidePreference from '@/models/RidePreference'
import { offerNext, withoutBusyDrivers, busyDriverIds, dispatchBoundsFor, cachedGlobalSettings } from '@/lib/dispatch'
import mongoose from 'mongoose'
import { chargedAtBooking, claimPrepayment, refundClaimedPrepayment, refundRefusedPrepayment, refundPrepayExcess, type Linked } from '@/lib/prepay'
import { quoteRental, type RentalQuote } from '@/lib/rental-pricing'
import { evaluatePromo, redeemPromo, releasePromo, type PromoResult } from '@/lib/promo'
import { verifyQuote, quoteCell, ENFORCE_QUOTES, stopsKey, weightKey, hireHours } from '@/lib/quote'
import { requireRider, requireActiveRider } from '@/lib/auth'
import { newRideOtp } from '@/lib/ride-otp'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { notStaleReviewFilter } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

const MAX_TIP = 500
const MAX_COD = 10000
/** Upper bound on a prepayment that may back a booking; any excess over what
 *  the booking needs is refunded to the wallet at once. */
const MAX_PREPAY = 100000
/** A booking this far ahead is a scheduled one (does not block a live ride). */
const SCHEDULED_AHEAD_MS = 10 * 60 * 1000

// The reply for a booking that already exists (retry / same clientRequestId).
function duplicateReply(r: any) {
  return {
    success: true, duplicate: true,
    ride: {
      id: r._id, otp: r.otp, status: r.status, fare: r.fare, tip: r.tip,
      totalFare: r.totalFare, commissionPercent: r.commissionPercent, distance: r.distance,
      duration: r.duration, routePolyline: r.routePolyline, fareBreakdown: r.fareBreakdown,
      couponCode: r.couponCode || '', couponDiscount: r.couponDiscount || 0,
      clientRequestId: r.clientRequestId,
    },
  }
}

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
    const s: any = await getSettingsAsync()
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

// Keeps only active admin-defined preference keys that apply to this service.
async function cleanPreferences(raw: any, service: string): Promise<string[] | undefined> {
  if (!Array.isArray(raw) || raw.length === 0) return undefined
  const keys = raw.map((k: any) => String(k)).slice(0, 10)
  const rows: any[] = await RidePreference.find({ key: { $in: keys }, isActive: true }).select('key services').lean()
  const ok = rows.filter(r => !r.services?.length || r.services.includes(service)).map(r => r.key)
  return ok.length ? ok : undefined
}

// POST booking → creates ride (status pending). Online matching drivers pick it up via polling.
//
// Outstation is paid BEFORE this call (wallet or Razorpay). If the booking is
// then refused — account on hold, quote expired, any error — before a ride
// exists, that payment backs nothing, so it is given back to the rider's Gora
// wallet right here and the reply says so (`refunded`). Once a ride exists,
// its money is handled by linkPrepayment and the cancel refunds instead.
export async function POST(req: NextRequest) {
  let b: any
  try { b = await req.json() } catch { return withCors({ error: 'Invalid request' }, 400) }
  if (!b || typeof b !== 'object') return withCors({ error: 'Invalid request' }, 400)
  const ctx = { rideCreated: false, refundHandled: false }
  const res = await book(req, b, ctx)
  if (res.status < 400 || ctx.rideCreated || ctx.refundHandled) return res

  const auth = requireRider(req) as any
  if (!auth?.id) return res
  const refund = await refundRefusedPrepayment(String(auth.id), b)
  if (!refund) return res
  const body = await res.clone().json().catch(() => ({}))
  return withCors({ ...body, refunded: refund.amount, refundedTo: 'wallet', walletBalance: refund.balance }, res.status)
}

async function book(req: NextRequest, b: any, ctx: { rideCreated: boolean; refundHandled: boolean }) {
  try {
    await connectDB()

    // The rider is whoever the token says — never a riderId from the body —
    // and the account must still be usable (not blocked/deleted, session live).
    const active = await requireActiveRider(req)
    if (!active.ok) {
      return active.code === 'UNAUTHORIZED'
        ? withCors({ error: 'Please sign in to book', code: 'unauthorized' }, 401)
        : withCors({ error: active.error, code: active.code }, active.status)
    }
    const riderId = String(active.id)
    const user: any = await User.findById(riderId).lean().catch(() => null)
    if (!user) return withCors({ error: 'Please sign in to book', code: 'unauthorized' }, 401)
    if (user.status === 'deleted') return withCors({ error: 'This account has been deleted.' }, 403)
    const hold = holdOf(user)
    if (hold.held) return withCors({ error: holdMessage(hold), accountHold: true, holdKind: hold.kind }, 403)
    const riderName = user.name || (typeof b.riderName === 'string' ? b.riderName.slice(0, 80) : undefined)
    const riderPhone = user.phone

    // Generate ride OTP (collection OTP for delivery)
    const otp = newRideOtp()
    // Delivery gets a second OTP for receiver handover
    const dropOtp = newRideOtp()

    const service = b.service || 'taxi'
    if (!['taxi', 'rental', 'outstation', 'delivery', 'hire_driver'].includes(service)) {
      return withCors({ error: 'Unknown service' }, 400)
    }

    // ── Money fields the rider may set: bounded here ──
    let tip = 0
    if (b.tip != null && b.tip !== '') {
      tip = Number(b.tip)
      if (typeof b.tip === 'boolean' || !Number.isFinite(tip) || tip < 0 || tip > MAX_TIP) {
        return withCors({ error: `Tip must be between ₹0 and ₹${MAX_TIP}`, code: 'invalidTip' }, 400)
      }
      tip = Math.round(tip)
    }
    let itemValue = 0
    if (b.itemValue != null && b.itemValue !== '') {
      itemValue = Number(b.itemValue)
      if (!Number.isFinite(itemValue) || itemValue < 0) return withCors({ error: 'Invalid item value' }, 400)
    }
    let codAmount = 0
    if (b.codAmount != null && b.codAmount !== '' && Number(b.codAmount) !== 0) {
      codAmount = Number(b.codAmount)
      const cap = Math.min(itemValue > 0 ? itemValue : Infinity, MAX_COD)
      if (service !== 'delivery') return withCors({ error: 'Cash on delivery is only for parcels', code: 'invalidCod' }, 400)
      if (!Number.isFinite(codAmount) || codAmount < 0 || codAmount > cap) {
        return withCors({ error: `Cash on delivery must be between ₹0 and ₹${cap}`, code: 'invalidCod' }, 400)
      }
      codAmount = Math.round(codAmount)
    }

    // ── Idempotency: the same clientRequestId returns the ride it made ──
    const clientRequestId = typeof b.clientRequestId === 'string' && b.clientRequestId.trim()
      ? b.clientRequestId.trim().slice(0, 64) : undefined
    if (clientRequestId) {
      const prev: any = await Ride.findOne({ riderId, clientRequestId }).lean()
      if (prev) return withCors(duplicateReply(prev))
    }

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
    if (b.pickupLat != null && b.pickupLng != null && !chargedAtBooking(service, b.paymentMode === 'cod' ? 'cash' : (b.paymentMode || 'cash'))) {
      const recent: any = await Ride.findOne({
        riderId, service, vehicleType: b.vehicleType, status: 'pending',
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
      if (same) return withCors(duplicateReply(recent))
    }

    // ── One live ride at a time (a future scheduled booking does not count) ──
    const soon = Date.now() + SCHEDULED_AHEAD_MS
    const isFuture = (v: unknown) => (clientTime(v)?.getTime() ?? 0) > soon
    const newIsScheduled = isFuture(b.scheduledAt) || isFuture(b.departureAt) || isFuture(b.hireStartAt)
    if (!newIsScheduled) {
      const later = new Date(soon)
      const active: any = await Ride.findOne({
        riderId, status: { $in: ['pending', 'accepted', 'arrived', 'ongoing'] },
        $nor: [
          { status: { $in: ['pending', 'accepted'] }, scheduledAt: { $gt: later } },
          { status: { $in: ['pending', 'accepted'] }, departureAt: { $gt: later } },
          { status: { $in: ['pending', 'accepted'] }, hireStartAt: { $gt: later } },
        ],
        // A ride flagged for review more than 30 min ago no longer blocks booking.
        $and: [notStaleReviewFilter()],
      }).select('_id status service').lean()
      if (active) {
        return withCors({
          error: 'You already have a ride in progress. Finish or cancel it before booking another.',
          code: 'activeRide', activeRideId: String(active._id), activeRideStatus: active.status,
        }, 409)
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
    let computedFare = Number(b.fare) || 0
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
    let couponRedeemed = false
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
      if (!Number.isFinite(computedFare) || computedFare <= 0) {
        return withCors({ error: 'This fare is not valid. Please refresh and try again.', code: 'invalidFare' }, 400)
      }

      // A rental's fare has its (server-validated) coupon taken off here, as
      // before; every other service keeps the full fare (see below).
      promo = await evaluatePromo(b.couponCode, computedFare, pickupZone?._id, { service, riderId })  // where the pickup is, never a zone the client names
      if (promo.applied && !(await redeemPromo(promo, riderId))) promo = { ...promo, discount: 0, applied: false, reason: 'You have already used this code' }
      if (promo.applied) { couponRedeemed = true; computedFare = Math.max(0, computedFare - promo.discount) }
    }

    // ── Non-rental services: the fare must be one WE signed ──
    // book cannot recompute outstation/hire/delivery pricing without duplicating
    // those formulas (and risking drift from the quoted price), so /fare/estimate
    // signs the fare it just produced and we verify it here.
    let quoteWarning: string | null = null
    let signed: Record<string, string | number> | null = null
    if (service !== 'rental') {
      // Everything else that changes the price must match what was signed.
      const tripType = String(b.tripType || 'one_way')
      const x: Record<string, string | number> =
        service === 'outstation' ? { tripType, stops: stopsKey(Array.isArray(b.multiStops) && b.multiStops.length ? b.multiStops : b.stops) }
        : service === 'hire_driver' ? { tripType, hours: hireHours(b.hireTotalHours) }
        : service === 'delivery' ? { weight: weightKey(b.weightKg), stops: stopsKey(b.stops) }
        : {}
      let check = verifyQuote(b.quoteToken, {
        service,
        vehicleType: b.vehicleType,
        // Hire is priced on hours alone, so /fare/estimate signs it without a
        // drop; the rider app still sends one (pickup again), so ignore it here.
        cell: service === 'hire_driver'
          ? quoteCell(b.pickupLat, b.pickupLng, null, null)
          : quoteCell(b.pickupLat, b.pickupLng, b.dropLat, b.dropLng),
        x,
      })
      // Taxi stops: installed rider apps quote WITHOUT stops and book with
      // them, so a stop-less quote is still accepted (logged); a quote that
      // was signed WITH stops must match them exactly.
      if (check.ok && service === 'taxi') {
        const want = stopsKey(b.stops)
        const got = String(check.x.stops ?? '')
        if (got !== want) {
          if (got) check = { ok: false, reason: 'Quote stops mismatch' }
          else console.warn('[book] taxi stops not in quote (old app)', { stops: want })
        }
      }
      if (check.ok) {
        computedFare = check.fare        // authoritative: exactly what was quoted
        signed = check.x
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
    // Never a ride on a non-finite / zero / negative fare, whatever the quote
    // enforcement mode (an unsigned old-app fare included). A rental may reach
    // 0 only through its coupon (checked before the discount above).
    if (service !== 'rental' && (!Number.isFinite(fare) || fare <= 0)) {
      return withCors({ error: 'This fare is not valid. Please refresh and try again.', code: 'invalidFare' }, 400)
    }
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
    const totalFare = fare + tip

    // ── Coupon, every service except rental (done above): validated and
    // redeemed on the server; the fare stays full and the discount comes off
    // what the rider pays at completion (lib/settlement.ts). Gora funds it.
    if (service !== 'rental') {
      promo = await evaluatePromo(b.couponCode, fare, pickupZone?._id, { service, riderId })
      if (promo.applied && !(await redeemPromo(promo, riderId))) promo = { ...promo, discount: 0, applied: false, reason: 'You have already used this code' }
      if (promo.applied) couponRedeemed = true
    }
    const couponDiscount = promo?.applied ? promo.discount : 0
    const releaseCoupon = async () => { if (couponRedeemed && promo) await releasePromo(promo.code, promo.source, riderId) }

    // ── Hire: hours and rate are the server's (signed quote / zone pricing) ──
    const hireTotalHours = service === 'hire_driver'
      ? (Number(signed?.hours) || hireHours(b.hireTotalHours)) : 0
    const hirePerHour = service === 'hire_driver'
      ? (signed?.perHour != null ? Number(signed.perHour) || 0 : Number(pricingRow?.perHour) || 0) : 0

    // Installed builds of the rider app send 'cod' for a parcel with cash on
    // delivery switched on. The Ride schema only accepts cash / wallet / online,
    // so every such booking failed validation and was never created. With COD on,
    // the app has always collected the fare as cash, so that is what it is.
    const paymentMode = b.paymentMode === 'cod' ? 'cash' : (b.paymentMode || 'cash')
    if (!['cash', 'wallet', 'online'].includes(paymentMode)) { await releaseCoupon(); return withCors({ error: 'Invalid payment mode' }, 400) }

    // ── Charged at booking (outstation wallet/online): no verified payment
    // covering the fare, no ride. Claimed against the id the ride will get, so
    // one payment can back one ride only; a short payment is given back.
    const rideObjectId = new mongoose.Types.ObjectId()
    let linked: Linked | null = null
    // What must be prepaid: the whole trip as booked — fare + tip − coupon. The
    // tip is part of it: settlement credits the driver the tip, so prepaying
    // without it left Gora paying the driver's tip.
    let required = 0
    if (chargedAtBooking(service, paymentMode)) {
      required = Math.max(0, Math.round(fare + tip - couponDiscount))
      linked = await claimPrepayment({ _id: rideObjectId, service, paymentMode, fare, totalFare, createdAt: new Date(), maxPrepay: MAX_PREPAY }, riderId, b)
      if (!linked || linked.amount < required - 1) {
        await releaseCoupon()
        let refund = null
        if (linked) { refund = await refundClaimedPrepayment(riderId, linked); ctx.refundHandled = true }
        return withCors({
          error: linked
            ? `Your payment of ₹${linked.amount} does not cover the ₹${required} fare. It was added to your Gora wallet; please pay again.`
            : `Please pay ₹${required} to book this trip.`,
          code: 'prepaymentRequired', amountDue: required, fare, tip, couponDiscount,
          ...(refund ? { refunded: refund.amount, refundedTo: 'wallet', walletBalance: refund.balance } : {}),
        }, 402)
      }
    }

    let ride: any
    try {
    ride = await Ride.create({
      _id: rideObjectId,
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
      preferences: await cleanPreferences(b.preferences, service),
      preferFemaleDriver: !!b.preferFemaleDriver,
      // Outstation-only fields (silently ignored for other services)
      tripType: b.tripType || 'one_way',
      cityFrom: b.cityFrom,
      cityTo: b.cityTo,
      departureAt: clientTime(b.departureAt),
      returnAt: clientTime(b.returnAt),
      numPassengers: b.numPassengers || 1,
      multiStops: Array.isArray(b.multiStops) ? b.multiStops : [],
      // From the signed quote's breakdown only, never the body.
      nightHaltCharge: service === 'outstation' ? Number(signed?.nh) || 0 : 0,
      emptyReturnCharge: service === 'outstation' ? Number(signed?.er) || 0 : 0,
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
      hireTotalHours,
      hirePerHour,
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
      itemValue,
      codAmount,
      // A rental booked for a future departureAt is a SCHEDULED ride. It used to
      // land only in `departureAt` (an outstation field), leaving scheduledAt
      // unset — so a rental booked for next week was broadcast to drivers
      // immediately and then aged out of the feed after 15 minutes.
      scheduledAt: clientTime(b.scheduledAt)
        ?? (service === 'rental' && (clientTime(b.departureAt)?.getTime() ?? 0) > Date.now() + 60_000
            ? clientTime(b.departureAt)
            : undefined),
      deliveryStops: Array.isArray(b.deliveryStops) && b.deliveryStops.length ? b.deliveryStops : undefined,
      // Charged before booking: the verified payment claimed above. Only what
      // the booking needs is kept; the excess is refunded right after create.
      ...(linked ? {
        prepaidAmount: Math.min(linked.amount, required), prepaidVia: linked.via, prepaidRef: linked.ref,
        ...(linked.amount > required ? { prepaidCaptured: linked.amount } : {}),
      } : {}),
      prepaidUnlinked: false,
      couponCode: promo?.applied ? promo.code : undefined,
      couponDiscount,
      couponSource: promo?.applied ? promo.source : undefined,
      clientRequestId,
    })
    } catch (e: any) {
      await releaseCoupon()
      if (linked) { await refundClaimedPrepayment(riderId, linked); ctx.refundHandled = true }
      // Two requests with the same clientRequestId: the other one won.
      if (e?.code === 11000 && clientRequestId) {
        const prev: any = await Ride.findOne({ riderId, clientRequestId }).lean()
        if (prev) return withCors(duplicateReply(prev))
      }
      throw e
    }
    // From here the payment belongs to this ride — a later error must not
    // also refund it.
    ctx.rideCreated = true

    // Paid more than the booking needs: the excess goes back to the wallet now.
    let excessRefunded = 0
    if (linked && linked.amount > required) {
      const excess = Math.round((linked.amount - required) * 100) / 100
      const r = await refundPrepayExcess(riderId, linked, excess)
      if (r) {
        excessRefunded = r.amount
        await Ride.updateOne({ _id: ride._id }, { $set: { prepaidExcessRefunded: r.amount } }).catch(() => {})
      }
    }

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
      // Same pickup-ETA cap as the offer ladder for an instant ride.
      const bounds = dispatchBoundsFor(ride, await cachedGlobalSettings())
      let ranked = rankCandidates(withoutBusyDrivers(drivers, busy), pickup, factor, new Map(), bounds).slice(0, ETA_CONFIG.CANDIDATE_POOL)

      if (ranked.length) {
        // Same traffic refinement the real dispatch ladder uses, via the shared
        // helper rather than a second hand-rolled copy of the matrix call. The
        // cached leg from offerNext() above is almost always reused here, so
        // this costs nothing extra when the flag is on.
        if (MATRIX_REFINE.DISPATCH) {
          ranked = await refineCandidatesWithTraffic(ranked, pickup, bounds)
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
        couponCode: ride.couponCode || '', couponDiscount,
        // What the rider will pay at the end for this fare (before any extras).
        payableEstimate: Math.max(0, Math.round(totalFare - (service === 'rental' ? 0 : couponDiscount) - (linked ? Math.min(linked.amount, required) : 0))),
        ...(linked ? { prepaidAmount: Math.min(linked.amount, required) } : {}),
        ...(excessRefunded > 0 ? { prepaidExcessRefunded: excessRefunded, refundedTo: 'wallet' } : {}),
        hireTotalHours: service === 'hire_driver' ? hireTotalHours : undefined,
        hirePerHour: service === 'hire_driver' ? hirePerHour : undefined,
        clientRequestId,
      },
      // Lets the app show "coupon expired" rather than silently charging full price.
      promo: promo && promo.code ? promo : null,
      rentalPackage: rentalQuote,
      quoteWarning,
      driverFound: !!nearest,
      offeredDriverId,
      // Preview only: no id, no phone — the driver's contact is shared once a
      // driver actually accepts (GET /rides/:id).
      driver: nearest
        ? { name: nearest.name, distanceKm: nearestKm, etaMin: nearestEtaMin }
        : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
