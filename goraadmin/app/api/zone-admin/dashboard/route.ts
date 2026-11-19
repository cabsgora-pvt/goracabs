export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { guardZoneAdmin } from '@/lib/zone-admin'
import { ETA_CONFIG } from '@/lib/eta'

// Figures for the signed-in zone admin's zones only.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req)
  if ('denied' in g) return g.denied
  try {
    const zoneObjIds = g.zoneIds.map(id => new mongoose.Types.ObjectId(id))
    // Midnight IST, whatever the server's own timezone (UTC on the VPS).
    const IST = 5.5 * 3600e3
    const startOfDay = new Date(Math.floor((Date.now() + IST) / 864e5) * 864e5 - IST)
    const fresh = new Date(Date.now() - ETA_CONFIG.LOCATION_FRESH_MS)
    const sum = (match: any) => Ride.aggregate([
      { $match: match },
      { $group: { _id: null, n: { $sum: 1 }, fare: { $sum: { $ifNull: ['$totalFare', 0] } } } },
    ])
    const [totalRides, today, allTime, ongoing, drivers, onlineDrivers, recent] = await Promise.all([
      Ride.countDocuments({ zoneId: { $in: zoneObjIds } }),
      sum({ zoneId: { $in: zoneObjIds }, status: 'completed', completedAt: { $gte: startOfDay } }),
      sum({ zoneId: { $in: zoneObjIds }, status: 'completed' }),
      Ride.countDocuments({ zoneId: { $in: zoneObjIds }, status: { $in: ['accepted', 'arrived', 'ongoing'] } }),
      Driver.countDocuments({ zoneId: { $in: g.zoneIds } }),
      Driver.countDocuments({ zoneId: { $in: g.zoneIds }, isOnline: true, locationUpdatedAt: { $gte: fresh } }),
      Ride.find({ zoneId: { $in: zoneObjIds } }).sort({ createdAt: -1 }).limit(8)
        .select('riderName driverName pickupAddress dropAddress service vehicleType totalFare status createdAt').lean(),
    ])
    return NextResponse.json({
      totalRides, ongoingRides: ongoing, drivers, onlineDrivers,
      todayRides: today[0]?.n || 0, todayRevenue: today[0]?.fare || 0,
      completedRides: allTime[0]?.n || 0, totalRevenue: allTime[0]?.fare || 0,
      recentRides: recent,
    })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
