export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET ?pickupLat=..&pickupLng=..&vehicleType=optional
// Returns active rental packages for the pickup zone, grouped per vehicle, with driver ETA.
export async function GET(req: NextRequest) {
  try {
    const sp = req.nextUrl.searchParams
    const pickupLat = parseFloat(sp.get('pickupLat') || '')
    const pickupLng = parseFloat(sp.get('pickupLng') || '')
    if (Number.isNaN(pickupLat) || Number.isNaN(pickupLng)) {
      return withCors({ error: 'pickup required' }, 400)
    }

    await connectDB()
    const zones = await Zone.find({ isActive: true }).lean() as any[]

    // Resolve pickup zone
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
      if (!zone || nd > 25) return withCors({ available: false, message: 'Rental not available here' })
    }

    const packages = (zone.rentalPackages || []).filter((p: any) => p.isActive !== false)
    if (!packages.length) return withCors({ available: false, message: 'No rental packages configured for this zone' })

    // Online + rental-accepting drivers, nearest per vehicle type
    const drivers: any[] = await Driver.find({
      status: 'approved', isOnline: true, acceptsRental: true,
      currentLat: { $ne: null }, currentLng: { $ne: null },
    }).select('selectedVehicleTypeName currentLat currentLng').lean()
    const nearestByType = new Map<string, number>()
    for (const d of drivers) {
      const t = d.selectedVehicleTypeName
      if (!t) continue
      const km = distanceKm({ lat: pickupLat, lng: pickupLng }, { lat: d.currentLat, lng: d.currentLng })
      const prev = nearestByType.get(t)
      if (prev == null || km < prev) nearestByType.set(t, km)
    }

    // Attach vehicle image + ETA to each package
    const vts: any[] = await VehicleType.find({ isActive: true }).select('name imageUrl capacity').lean()
    const vtByName = new Map<string, any>(vts.map(v => [v.name, v]))

    const result = packages.map((p: any) => {
      const km = nearestByType.get(p.vehicleTypeName)
      const vt = vtByName.get(p.vehicleTypeName)
      return {
        id: p._id,
        vehicleTypeName: p.vehicleTypeName,
        imageUrl: vt?.imageUrl || '',
        capacity: vt?.capacity || 4,
        hours: p.hours,
        km: p.km,
        basePrice: p.basePrice,
        extraHourRate: p.extraHourRate,
        extraKmRate: p.extraKmRate,
        nightCharge: p.nightCharge,
        commissionPercent: p.commissionPercent ?? 20,
        etaMin: km != null ? Math.max(1, Math.min(30, Math.round(km * 2))) : null,
        driverDistanceKm: km != null ? +km.toFixed(1) : null,
      }
    })

    return withCors({
      available: true,
      zone: { id: zone._id, name: zone.name },
      packages: result,
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
