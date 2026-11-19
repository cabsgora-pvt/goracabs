export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Ride from '@/models/Ride'
import { guardZoneAdmin } from '@/lib/zone-admin'

// GET ?status=&page= — rides in the zone admin's zones, newest first.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req)
  if ('denied' in g) return g.denied
  try {
    const sp = req.nextUrl.searchParams
    const page = Math.max(1, parseInt(sp.get('page') || '1', 10) || 1)
    const limit = 25
    const q: any = { zoneId: { $in: g.zoneIds.map(id => new mongoose.Types.ObjectId(id)) } }
    const status = sp.get('status')
    if (status && ['pending', 'accepted', 'arrived', 'ongoing', 'completed', 'cancelled'].includes(status)) q.status = status
    const [rides, total] = await Promise.all([
      Ride.find(q).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit)
        .select('riderName driverName pickupAddress dropAddress service vehicleType totalFare status paymentMode createdAt').lean(),
      Ride.countDocuments(q),
    ])
    return NextResponse.json({ rides, total, page, pages: Math.max(1, Math.ceil(total / limit)) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
