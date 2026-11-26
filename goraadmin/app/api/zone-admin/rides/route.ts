export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Ride from '@/models/Ride'
import { guardZoneAdmin } from '@/lib/zone-admin'
import { parsePaging, escapeRegex } from '@/lib/list-params'
import { istDayStart } from '@/lib/finance'

const STATUSES = ['pending', 'accepted', 'arrived', 'ongoing', 'completed', 'cancelled']
const SERVICES = ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver']

// GET ?status=&service=&q=&from=YYYY-MM-DD&to=YYYY-MM-DD&page=&limit=
// Rides in the zone admin's zones, newest first. q matches rider / driver
// name or phone, an address, or the ride id. from / to are IST calendar days
// (inclusive) on the ride's creation time. Default 25 a page, at most 200.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req)
  if ('denied' in g) return g.denied
  try {
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 25)
    const q: any = { zoneId: { $in: g.zoneIds.map(id => new mongoose.Types.ObjectId(id)) } }
    const status = sp.get('status')
    if (status && STATUSES.includes(status)) q.status = status
    const service = sp.get('service')
    if (service && SERVICES.includes(service)) q.service = service
    const from = sp.get('from') ? istDayStart(String(sp.get('from'))) : null
    const toDay = sp.get('to') ? istDayStart(String(sp.get('to'))) : null
    if (from || toDay) {
      q.createdAt = {}
      if (from) q.createdAt.$gte = from
      if (toDay) q.createdAt.$lt = new Date(toDay.getTime() + 864e5)
    }
    const search = escapeRegex((sp.get('q') || '').trim())
    if (search) {
      const rx = { $regex: search, $options: 'i' }
      q.$or = [
        { riderName: rx }, { driverName: rx }, { riderPhone: rx }, { driverPhone: rx },
        { pickupAddress: rx }, { dropAddress: rx },
        ...(mongoose.isValidObjectId(search) && search.length === 24 ? [{ _id: new mongoose.Types.ObjectId(search) }] : []),
      ]
    }
    const [rides, total] = await Promise.all([
      Ride.find(q).sort({ createdAt: -1, _id: -1 }).skip(skip).limit(limit)
        .select('riderName driverName pickupAddress dropAddress service vehicleType totalFare status paymentMode createdAt').lean(),
      Ride.countDocuments(q),
    ])
    return NextResponse.json({ rides, total, page, limit, pages: Math.max(1, Math.ceil(total / limit)) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
