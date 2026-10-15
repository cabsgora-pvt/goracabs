export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { etaByVehicleType } from '@/lib/eta'
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

    // Rental-accepting drivers in THIS zone, ETA-ranked per vehicle type.
    // Previously this scanned every online driver in the country with no
    // freshness or busy filter, so it could advertise "2 min" from a driver in
    // another state whose app had been dead for hours.
    const etaByType = await etaByVehicleType(
      Driver,
      { lat: pickupLat, lng: pickupLng },
      { acceptsRental: true, allowRental: { $ne: false }, zoneId: String(zone._id) },
    )

    // Attach vehicle image + ETA to each package
    const vts: any[] = await VehicleType.find({ isActive: true }).select('name imageUrl capacity').lean()
    const vtByName = new Map<string, any>(vts.map(v => [v.name, v]))

    const result = packages.map((p: any) => {
      const eta = etaByType.get(p.vehicleTypeName)
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
        // null = no realistic driver for this vehicle type right now
        etaMin: eta?.min ?? null,
        driverDistanceKm: eta?.km ?? null,
        driversAvailable: eta?.available ?? 0,
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
