export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import Driver from '@/models/Driver'
import { guardZoneAdmin } from '@/lib/zone-admin'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Drivers registered in the zone admin's zones (names and phone numbers), for
// those whose plan includes driver management; actions are in drivers/[id].
// GET ?status=&q=&page=&limit= (default 50, newest first) — the true total,
// plus counts per status for the tabs.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'drivers' })
  if ('denied' in g) return g.denied
  try {
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 50)
    const base: any = { zoneId: { $in: g.zoneIds }, status: { $ne: 'deleted' } }
    const q: any = { ...base }
    const status = sp.get('status') || ''
    if (['pending', 'approved', 'blocked', 'rejected'].includes(status)) q.status = status
    const search = escapeRegex((sp.get('q') || '').trim())
    if (search) {
      const rx = { $regex: search, $options: 'i' }
      q.$or = [{ name: rx }, { phone: rx }, { vehicleNumber: rx }, { vehicleRegistrationNumber: rx }]
    }
    const [drivers, total, byStatus] = await Promise.all([
      Driver.find(q)
        .select('name phone status isOnline selectedVehicleTypeName vehicleNumber vehicleModel rating totalRides profilePicUrl createdAt zoneId')
        .sort({ createdAt: -1, _id: 1 }).skip(skip).limit(limit).lean(),
      Driver.countDocuments(q),
      Driver.aggregate([{ $match: base }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
    ])
    const counts: Record<string, number> = {}
    for (const b of byStatus) counts[b._id || 'pending'] = b.n
    return NextResponse.json({ drivers, total, page, limit, pages: Math.max(1, Math.ceil(total / limit)), counts })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
