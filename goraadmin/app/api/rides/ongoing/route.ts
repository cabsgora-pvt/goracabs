export const dynamic = 'force-dynamic'
import { NextResponse , NextRequest} from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

// Admin pages only. It answered anyone with every matching ride and rider.
//
// GET ?page&limit (max 200) → { rides, total, page, limit, drivers, idleDrivers?, at }
//   rides: accepted / arrived / ongoing (&pending=1 adds requests still
//   looking for a driver), newest activity first, without the chat.
//   drivers: { [driverId]: { lat, lng, heading, at, isOnline } } — the live
//   position of each listed ride's driver (Driver.currentLat/Lng).
//   &idle=1 adds idleDrivers: online drivers with a fix in the last 10 min who
//   are on none of these rides (max 500).
//   Each ride also carries locationStale: its driver sent no position for
//   STALE_MS (or never) — the page highlights these as "stuck".
const STALE_MS = 10 * 60_000

export async function GET(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 200)
    const statuses = ['accepted', 'arrived', 'ongoing', ...(sp.get('pending') === '1' ? ['pending'] : [])]
    const q = { status: { $in: statuses } }
    const [rides, total] = await Promise.all([
      Ride.find(q).sort({ updatedAt: -1 }).skip(skip).limit(limit).select('-messages -routePolyline -offeredHistory -rejectedBy').lean(),
      Ride.countDocuments(q),
    ])
    const ids = Array.from(new Set(rides.map((r: any) => r.driverId && String(r.driverId)).filter(Boolean)))
    const ds: any[] = ids.length
      ? await Driver.find({ _id: { $in: ids } }).select('currentLat currentLng currentHeading locationUpdatedAt isOnline').lean()
      : []
    const drivers: Record<string, any> = {}
    for (const d of ds) {
      drivers[String(d._id)] = { lat: d.currentLat ?? null, lng: d.currentLng ?? null, heading: d.currentHeading || 0, at: d.locationUpdatedAt || null, isOnline: !!d.isOnline }
    }
    const now = Date.now()
    const out = rides.map((r: any) => {
      const d = r.driverId ? drivers[String(r.driverId)] : null
      const stale = !!r.driverId && (!d?.at || now - new Date(d.at).getTime() > STALE_MS)
      return { ...r, locationStale: stale }
    })
    let idleDrivers: any[] | undefined
    if (sp.get('idle') === '1') {
      idleDrivers = await Driver.find({
        _id: { $nin: ids }, isOnline: true, currentLat: { $ne: null },
        locationUpdatedAt: { $gte: new Date(now - STALE_MS) },
      }).select('name selectedVehicleTypeName vehicleNumber currentLat currentLng locationUpdatedAt').limit(500).lean()
    }
    return NextResponse.json({ rides: out, total, page, limit, drivers, ...(idleDrivers ? { idleDrivers } : {}), at: new Date() })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
