export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
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
    const { pickupLat, pickupLng, dropLat, dropLng, service = 'taxi', tripType = 'one_way' } = await req.json()
    if (pickupLat == null || pickupLng == null) return withCors({ error: 'pickup required' }, 400)

    await connectDB()

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

      // Build vehicles list — prefer per-zone pricing; fall back to a flat estimate if none configured
      let vehicles: any[]
      if (outstationPricing.length) {
        vehicles = outstationPricing.map((p: any) => {
          const distanceCharge = totalKm * (p.perKm || 0)
          const timeCharge = totalMin * (p.perMin || 0)
          let fare = Math.round((p.baseFare || 0) + distanceCharge + timeCharge)
          fare = Math.max(fare, p.minFare || 0)
          const eta = nearestByType.get(p.vehicleTypeName)
          return {
            vehicleTypeId: p.vehicleTypeId,
            name: p.vehicleTypeName,
            fare,
            baseFare: p.baseFare,
            perKm: p.perKm,
            perMin: p.perMin,
            commissionPercent: p.commissionPercent ?? 20,
            etaMin: eta ? eta.min : null,
            driverDistanceKm: eta ? eta.km : null,
          }
        })
      } else {
        // Sensible default fallback so users can still see prices even before admin configures outstation pricing
        const fallback = [
          { name: 'Economy', perKm: 12, base: 500 },
          { name: 'Sedan',   perKm: 14, base: 700 },
          { name: 'SUV',     perKm: 18, base: 1000 },
          { name: 'Premium', perKm: 22, base: 1500 },
        ]
        vehicles = fallback.map(v => {
          const eta = nearestByType.get(v.name)
          return {
            name: v.name,
            fare: Math.round(v.base + totalKm * v.perKm),
            baseFare: v.base,
            perKm: v.perKm,
            perMin: 0,
            commissionPercent: 20,
            etaMin: eta ? eta.min : null,
            driverDistanceKm: eta ? eta.km : null,
          }
        })
      }

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

    // Distance & time (Haversine — replaced by Directions API at booking time)
    let distance = 5, duration = 15
    if (dropLat != null && dropLng != null) {
      distance = +distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: dropLat, lng: dropLng }).toFixed(1)
      duration = Math.round(distance * 3) // ~3 min/km estimate
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

    // Calculate fare + attach ETA per active vehicle for this service
    const vehicles = (zone.pricing || [])
      .filter((p: any) => p.service === service)
      .map((p: any) => {
        const baseDist = 2 // free km in base
        const chargeableKm = Math.max(0, distance - baseDist)
        let fare = (p.baseFare || 0) + chargeableKm * (p.perKm || 0) + duration * (p.perMin || 0)
        fare = Math.max(fare, p.minFare || 0)
        fare = Math.round(fare)
        const eta = nearestByType.get(p.vehicleTypeName)
        return {
          vehicleTypeId: p.vehicleTypeId,
          name: p.vehicleTypeName,
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
