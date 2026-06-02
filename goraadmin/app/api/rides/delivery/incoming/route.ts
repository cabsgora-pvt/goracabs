export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → parcels addressed TO the authenticated user (matched by their phone = receiverPhone)
export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    let phone = (payload.phone || '').toString().replace(/\D/g, '').slice(-10)
    if (!phone) {
      const u: any = await User.findById(payload.id).select('phone').lean()
      phone = (u?.phone || '').toString().replace(/\D/g, '').slice(-10)
    }
    if (!phone) return withCors({ rides: [] })
    // Match last-10-digits of receiverPhone
    const all: any[] = await Ride.find({ service: 'delivery' }).sort({ createdAt: -1 }).limit(100).lean()
    const mine = all.filter(r => (r.receiverPhone || '').replace(/\D/g, '').slice(-10) === phone)

    const driverIds = Array.from(new Set(mine.map(r => r.driverId).filter(Boolean).map(String)))
    const drivers = driverIds.length ? await Driver.find({ _id: { $in: driverIds } }).select('name profilePicUrl vehicleModel vehicleNumber').lean() as any[] : []
    const dMap = new Map(drivers.map(d => [String(d._id), d]))

    const rides = mine.map(r => ({
      ...r,
      driver: r.driverId ? (() => { const d = dMap.get(String(r.driverId)); return d ? { name: d.name, profilePicUrl: d.profilePicUrl, vehicleModel: d.vehicleModel, vehicleNumber: d.vehicleNumber } : null })() : null,
    }))
    return withCors({ rides })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
