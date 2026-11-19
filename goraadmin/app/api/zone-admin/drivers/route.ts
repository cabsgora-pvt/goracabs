export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import Driver from '@/models/Driver'
import { guardZoneAdmin } from '@/lib/zone-admin'

// Drivers registered in the zone admin's zones (names and phone numbers), for
// those whose plan includes driver management; actions are in drivers/[id].
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'drivers' })
  if ('denied' in g) return g.denied
  try {
    const drivers = await Driver.find({ zoneId: { $in: g.zoneIds } })
      .select('name phone status isOnline selectedVehicleTypeName vehicleNumber vehicleModel rating totalRides profilePicUrl createdAt zoneId')
      .sort({ createdAt: -1 }).limit(500).lean()
    return NextResponse.json({ drivers })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
