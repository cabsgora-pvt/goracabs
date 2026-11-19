export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Zone from '@/models/Zone'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import { guardZoneAdmin } from '@/lib/zone-admin'
import { ETA_CONFIG } from '@/lib/eta'

// Live map of their zones: boundaries, online drivers with a fresh position,
// and rides under way.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'live_map' })
  if ('denied' in g) return g.denied
  try {
    const fresh = new Date(Date.now() - ETA_CONFIG.LOCATION_FRESH_MS)
    const [zones, drivers, rides] = await Promise.all([
      Zone.find({ _id: { $in: g.zoneIds } }).select('name polygonPath centerLat centerLng').lean(),
      Driver.find({ zoneId: { $in: g.zoneIds }, isOnline: true, locationUpdatedAt: { $gte: fresh }, currentLat: { $ne: null } })
        .select('name phone selectedVehicleTypeName vehicleNumber currentLat currentLng').lean(),
      Ride.find({ zoneId: { $in: g.zoneIds.map(id => new mongoose.Types.ObjectId(id)) }, status: { $in: ['pending', 'accepted', 'arrived', 'ongoing'] } })
        .select('riderName driverName driverId pickupLat pickupLng dropLat dropLng pickupAddress dropAddress status service vehicleType createdAt').lean(),
    ])
    return NextResponse.json({ zones, drivers, rides, at: new Date() })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
