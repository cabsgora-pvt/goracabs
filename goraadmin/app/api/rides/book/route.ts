export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Zone from '@/models/Zone'
import { distanceKm, pointInPolygon } from '@/lib/geo'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

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

    // Generate ride OTP
    const otp = Math.floor(1000 + Math.random() * 9000).toString()

    const service = b.service || 'taxi'

    // Resolve zone: use provided zoneId, else auto-detect from pickup coords
    let zone: any = null
    if (b.zoneId) {
      zone = await Zone.findById(b.zoneId).lean().catch(() => null)
    }
    if (!zone && b.pickupLat != null && b.pickupLng != null) {
      const zones = await Zone.find({ isActive: true }).lean() as any[]
      for (const z of zones) {
        if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: b.pickupLat, lng: b.pickupLng }, z.polygonPath)) {
          zone = z; break
        }
      }
      if (!zone) {
        let nd = Infinity
        for (const z of zones) {
          const d = distanceKm({ lat: b.pickupLat, lng: b.pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
          if (d < nd) { nd = d; zone = z }
        }
        if (nd > 25) zone = null
      }
    }
    const zoneId = b.zoneId || (zone ? zone._id : undefined)

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
    if (b.pickupLat != null && b.pickupLng != null && b.dropLat != null && b.dropLng != null) {
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

    const fare = computedFare
    const tip = b.tip || 0
    const totalFare = fare + tip

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
      paymentMode: b.paymentMode || 'cash',
      zoneId, otp, status: 'pending',
      // Outstation-only fields (silently ignored for other services)
      tripType: b.tripType || 'one_way',
      cityFrom: b.cityFrom,
      cityTo: b.cityTo,
      departureAt: b.departureAt ? new Date(b.departureAt) : undefined,
      returnAt: b.returnAt ? new Date(b.returnAt) : undefined,
      numPassengers: b.numPassengers || 1,
      multiStops: Array.isArray(b.multiStops) ? b.multiStops : [],
      nightHaltCharge: b.nightHaltCharge || 0,
      emptyReturnCharge: b.emptyReturnCharge || 0,
      // Rental-only fields (silently ignored for other services)
      packageHours: b.packageHours || 0,
      packageKm: b.packageKm || 0,
      extraHourRate: b.extraHourRate || 0,
      extraKmRate: b.extraKmRate || 0,
      nightChargeRental: b.nightChargeRental || 0,
      rentalPhase: service === 'rental' ? 'pending' : undefined,
      // Hire-a-driver fields
      hireStartAt: b.hireStartAt ? new Date(b.hireStartAt) : undefined,
      hireEndAt: b.hireEndAt ? new Date(b.hireEndAt) : undefined,
      hireTotalHours: b.hireTotalHours || 0,
      hirePerHour: b.hirePerHour || 0,
      transmission: b.transmission || '',
    })

    // Find nearest online approved driver: same zone + vehicle type
    const drivers = await Driver.find({
      status: 'approved', isOnline: true,
      ...(zoneId ? { zoneId: String(zoneId) } : {}),
      selectedVehicleTypeName: b.vehicleType,
    }).lean() as any[]

    let nearest: any = null, nd = Infinity
    for (const d of drivers) {
      if (d.currentLat == null) continue
      const dist = distanceKm({ lat: b.pickupLat, lng: b.pickupLng }, { lat: d.currentLat, lng: d.currentLng })
      if (dist < nd) { nd = dist; nearest = d }
    }

    return withCors({
      success: true,
      ride: {
        id: ride._id, otp, status: 'pending', fare, tip, totalFare, commissionPercent,
        distance: roadDistanceKm, duration: roadDurationMin, routePolyline, fareBreakdown: breakdown,
      },
      driverFound: !!nearest,
      driver: nearest ? { id: nearest._id, name: nearest.name, phone: nearest.phone, distanceKm: +nd.toFixed(1) } : null,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
