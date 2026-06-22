export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// Ask Google for road distance + duration (used by outstation fare)
async function fetchDirections(originLat: number, originLng: number, destLat: number, destLng: number) {
  try {
    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return null
    const url = `https://maps.googleapis.com/maps/api/directions/json?origin=${originLat},${originLng}&destination=${destLat},${destLng}&mode=driving&key=${key}`
    const r = await fetch(url)
    const data = await r.json()
    if (data.status !== 'OK' || !data.routes?.length) return null
    const leg = data.routes[0].legs?.[0] || {}
    return {
      distanceKm: +((leg.distance?.value || 0) / 1000).toFixed(1),
      durationMin: Math.round((leg.duration?.value || 0) / 60),
    }
  } catch { return null }
}

// POST { pickupLat, pickupLng, dropLat, dropLng, service, tripType? }
// → returns zone + list of vehicles with calculated fare + real ETA (nearest driver) per vehicle type
export async function POST(req: NextRequest) {
  try {
    const { pickupLat, pickupLng, dropLat, dropLng, service = 'taxi', tripType = 'one_way', totalHours = 0, weightKg = 0, stops = [] } = await req.json()
    if (pickupLat == null || pickupLng == null) return withCors({ error: 'pickup required' }, 400)

    await connectDB()

    // ── Hire a Driver: customer's own car, priced by hours × perHour per vehicle type ──
    if (service === 'hire_driver') {
      const zonesH = await Zone.find({ isActive: true }).lean() as any[]
      let zoneH: any = null
      for (const z of zonesH) {
        if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: pickupLat, lng: pickupLng }, z.polygonPath)) { zoneH = z; break }
      }
      if (!zoneH) {
        let nd = Infinity
        for (const z of zonesH) {
          const d = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
          if (d < nd) { nd = d; zoneH = z }
        }
        if (!zoneH || nd > 25) return withCors({ available: false, message: 'Hire a Driver not available here' })
      }
      const hours = Math.max(1, Math.ceil(totalHours || 0))
      const hirePricing = (zoneH.pricing || []).filter((p: any) => p.service === 'hire_driver' && p.isActive !== false)
      const drv: any[] = await Driver.find({ status: 'approved', isOnline: true, acceptsHireDriver: true, currentLat: { $ne: null } })
        .select('selectedVehicleTypeName currentLat currentLng').lean()
      const nearH = new Map<string, number>()
      for (const d of drv) {
        const t = d.selectedVehicleTypeName; if (!t) continue
        const km = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: d.currentLat, lng: d.currentLng })
        if (nearH.get(t) == null || km < nearH.get(t)!) nearH.set(t, km)
      }
      // Vehicle images + capacity by type name
      const vtsH: any[] = await VehicleType.find({ isActive: true }).select('name imageUrl capacity').lean()
      const vtMapH = new Map<string, any>(vtsH.map(v => [v.name, v]))
      const vehicles = hirePricing.map((p: any) => {
        const perHour = p.perHour || 0
        const fare = Math.max(p.minFare || 0, Math.round((p.baseFare || 0) + hours * perHour))
        const km = nearH.get(p.vehicleTypeName)
        const vt = vtMapH.get(p.vehicleTypeName)
        return {
          vehicleTypeId: p.vehicleTypeId, name: p.vehicleTypeName,
          imageUrl: vt?.imageUrl || '', capacity: vt?.capacity || 4,
          fare, perHour, baseFare: p.baseFare || 0, commissionPercent: p.commissionPercent ?? 20,
          etaMin: km != null ? Math.max(1, Math.min(30, Math.round(km * 2))) : null,
        }
      })
      return withCors({ available: true, zone: { id: zoneH._id, name: zoneH.name }, service: 'hire_driver', totalHours: hours, vehicles })
    }

    // ── Outstation: city-to-city, no zone restriction, use Directions API + outstation pricing ──
    if (service === 'outstation') {
      if (dropLat == null || dropLng == null) return withCors({ error: 'drop required for outstation' }, 400)

      // Road distance + duration via Google Directions (fallback to Haversine + 1.3 multiplier if API fails)
      let oneWayKm = 0, oneWayMin = 0
      const dir = await fetchDirections(pickupLat, pickupLng, dropLat, dropLng)
      if (dir) {
        oneWayKm = dir.distanceKm
        oneWayMin = dir.durationMin
      } else {
        oneWayKm = +(distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: dropLat, lng: dropLng }) * 1.3).toFixed(1)
        oneWayMin = Math.round(oneWayKm)
      }
      const totalKm = tripType === 'round_trip' ? +(oneWayKm * 2).toFixed(1) : oneWayKm
      const totalMin = tripType === 'round_trip' ? oneWayMin * 2 : oneWayMin

      // Look up outstation pricing per vehicle type from the pickup zone (else default to global ServiceConfig pricing)
      let pickupZone: any = null
      const zonesAll: any[] = await Zone.find({ isActive: true }).lean() as any[]
      for (const z of zonesAll) {
        if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: pickupLat, lng: pickupLng }, z.polygonPath)) {
          pickupZone = z; break
        }
      }
      const outstationPricing = (pickupZone?.pricing || []).filter((p: any) => p.service === 'outstation')

      // Online outstation-accepting drivers, group nearest by vehicle type
      const odrivers: any[] = await Driver.find({
        status: 'approved',
        isOnline: true,
        acceptsOutstation: true,
        currentLat: { $ne: null },
        currentLng: { $ne: null },
      }).select('selectedVehicleTypeName currentLat currentLng').lean()
      const nearestByType = new Map<string, { km: number; min: number }>()
      for (const d of odrivers) {
        const t = d.selectedVehicleTypeName
        if (!t) continue
        const km = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: d.currentLat, lng: d.currentLng })
        const prev = nearestByType.get(t)
        if (!prev || km < prev.km) {
          const min = Math.max(1, Math.min(30, Math.round(km * 2)))
          nearestByType.set(t, { km: +km.toFixed(1), min })
        }
      }

      // Pull every active vehicle type that admin has marked as supporting outstation.
      // For each: prefer the zone's outstation override pricing; fall back to the vehicle's own
      // baseFare/perKm (configured on the VehicleType doc itself).
      const vts: any[] = await VehicleType.find({
        services: 'outstation',
        isActive: true,
      }).sort({ sortOrder: 1, name: 1 }).lean()

      const pricingByName = new Map<string, any>()
      for (const p of outstationPricing) pricingByName.set(p.vehicleTypeName, p)

      const vehicles = vts.map(v => {
        const p = pricingByName.get(v.name)
        const baseFare = p?.baseFare ?? v.baseFare ?? 0
        const perKm    = p?.perKm    ?? v.perKm    ?? 0
        const perMin   = p?.perMin   ?? v.perMin   ?? 0
        const minFare  = p?.minFare  ?? v.minFare  ?? 0
        const commission = p?.commissionPercent ?? 20
        const nightHaltCharge   = p?.nightHaltCharge    ?? 0
        const emptyReturnPercent= p?.emptyReturnPercent ?? 0

        let subtotal = baseFare + totalKm * perKm + totalMin * perMin
        let extras = 0
        const breakdown: any = {}
        // Empty-return surcharge (only one-way trips)
        if (tripType !== 'round_trip' && emptyReturnPercent > 0) {
          const er = Math.round((subtotal * emptyReturnPercent) / 100)
          extras += er
          breakdown.emptyReturn = er
        }
        // Night-halt charge (round trip — assume 1 night per 8 hours of travel beyond same-day)
        if (tripType === 'round_trip' && nightHaltCharge > 0) {
          // Round-trip totalMin already x2; if > 8 hours each way, charge per overnight stop
          const oneWayHours = oneWayMin / 60
          const nights = oneWayHours >= 6 ? 1 : 0 // simple heuristic — admin can tweak in future
          if (nights > 0) {
            const nh = nightHaltCharge * nights
            extras += nh
            breakdown.nightHalt = nh
            breakdown.nights = nights
          }
        }

        let fare = Math.round(subtotal + extras)
        fare = Math.max(fare, minFare)
        const eta = nearestByType.get(v.name)
        return {
          vehicleTypeId: v._id,
          name: v.name,
          imageUrl: v.imageUrl || '',
          capacity: v.capacity,
          fare,
          baseFare, perKm, perMin,
          commissionPercent: commission,
          nightHaltCharge, emptyReturnPercent,
          extras, breakdown,
          etaMin: eta ? eta.min : null,
          driverDistanceKm: eta ? eta.km : null,
          source: p ? 'zone' : 'vehicle',
        }
      })

      return withCors({
        available: true,
        zone: pickupZone ? { id: pickupZone._id, name: pickupZone.name } : null,
        distance: totalKm,
        duration: totalMin,
        oneWayKm,
        oneWayMin,
        service: 'outstation',
        tripType,
        vehicles,
      })
    }

    // ── Existing in-city flow (taxi / rental / delivery / hire_driver) ──
    const zones = await Zone.find({ isActive: true }).lean() as any[]

    // Find zone for pickup
    let zone: any = null
    for (const z of zones) {
      if (z.polygonPath?.length >= 3 && pointInPolygon({ lat: pickupLat, lng: pickupLng }, z.polygonPath)) {
        zone = z; break
      }
    }
    if (!zone) {
      let nd = Infinity
      for (const z of zones) {
        const d = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: z.centerLat || 0, lng: z.centerLng || 0 })
        if (d < nd) { nd = d; zone = z }
      }
      if (!zone || nd > 25) return withCors({ available: false, message: 'Service not available here' })
    }

    // ── Out-of-zone check for taxi/rental/delivery: if drop is OUTSIDE the pickup zone,
    //    tell the user to switch to Outstation (intercity). We only flag this when
    //    pickup actually fell inside a polygon (not a 25 km nearest-zone fallback).
    let outOfZone = false
    if (service === 'taxi' && dropLat != null && dropLng != null && zone?.polygonPath?.length >= 3) {
      const pickupInside = pointInPolygon({ lat: pickupLat, lng: pickupLng }, zone.polygonPath)
      const dropInside   = pointInPolygon({ lat: dropLat,    lng: dropLng    }, zone.polygonPath)
      if (pickupInside && !dropInside) outOfZone = true
    }
    if (outOfZone) {
      return withCors({
        available: true,
        outOfZone: true,
        zone: { id: zone._id, name: zone.name },
        message: `Your destination is outside ${zone.name} zone. Please switch to Outstation (Intercity) ride.`,
      })
    }

    // Distance & time (Haversine — replaced by Directions API at booking time).
    // With multi-stops: sum each leg pickup→stop1→stop2→…→drop.
    let distance = 5, duration = 15
    if (dropLat != null && dropLng != null) {
      const pts: Array<{ lat: number; lng: number }> = [{ lat: pickupLat, lng: pickupLng }]
      for (const s of (Array.isArray(stops) ? stops : [])) {
        if (s?.lat != null && s?.lng != null) pts.push({ lat: s.lat, lng: s.lng })
      }
      pts.push({ lat: dropLat, lng: dropLng })
      let total = 0
      for (let i = 0; i < pts.length - 1; i++) total += distanceKm(pts[i], pts[i + 1])
      distance = +total.toFixed(1)
      duration = Math.round(distance * 3)
    }

    // Load all approved+online drivers in this zone (one query, then bucket by vehicle type)
    const onlineDrivers: any[] = await Driver.find({
      status: 'approved',
      isOnline: true,
      zoneId: String(zone._id),
      currentLat: { $ne: null },
      currentLng: { $ne: null },
    }).select('selectedVehicleTypeName currentLat currentLng').lean()

    // For each vehicle type → nearest driver km + estimated min (assume ~30 km/h city avg)
    const nearestByType = new Map<string, { km: number; min: number }>()
    for (const d of onlineDrivers) {
      const t = d.selectedVehicleTypeName
      if (!t) continue
      const km = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: d.currentLat, lng: d.currentLng })
      const prev = nearestByType.get(t)
      if (!prev || km < prev.km) {
        // 30 km/h ≈ 2 min/km — clamp 1..30
        const min = Math.max(1, Math.min(30, Math.round(km * 2)))
        nearestByType.set(t, { km: +km.toFixed(1), min })
      }
    }

    // Vehicle images by type name (for delivery/taxi vehicle cards)
    const vtsAll: any[] = await VehicleType.find({ isActive: true }).select('name imageUrl capacity').lean()
    const vtImg = new Map<string, any>(vtsAll.map(v => [v.name, v]))

    // Calculate fare + attach ETA per active vehicle for this service
    const vehicles = (zone.pricing || [])
      .filter((p: any) => p.service === service)
      .map((p: any) => {
        const baseDist = 2 // free km in base
        const chargeableKm = Math.max(0, distance - baseDist)
        // Delivery adds a weight charge (perKg × kg); other services ignore it
        const weightCharge = service === 'delivery' ? (weightKg || 0) * (p.perKg || 0) : 0
        let fare = (p.baseFare || 0) + chargeableKm * (p.perKm || 0) + duration * (p.perMin || 0) + weightCharge
        fare = Math.max(fare, p.minFare || 0)
        fare = Math.round(fare)
        const eta = nearestByType.get(p.vehicleTypeName)
        const vt = vtImg.get(p.vehicleTypeName)
        return {
          vehicleTypeId: p.vehicleTypeId,
          name: p.vehicleTypeName,
          imageUrl: vt?.imageUrl || '', capacity: vt?.capacity || 4,
          fare,
          baseFare: p.baseFare,
          perKm: p.perKm,
          perMin: p.perMin,
          commissionPercent: p.commissionPercent ?? 20,
          // null = no driver currently available of this type
          etaMin: eta ? eta.min : null,
          driverDistanceKm: eta ? eta.km : null,
        }
      })

    return withCors({
      available: true,
      zone: { id: zone._id, name: zone.name },
      distance, duration, service,
      vehicles,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
