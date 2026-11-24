export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSAlert from '@/models/SOSAlert'
import mongoose from 'mongoose'
import { requireAdmin, requireDriverAuth, requireRider } from '@/lib/auth'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// POST — raise an SOS alert (called by rider or driver apps when SOS is tapped).
// GET  — admin lists alerts (newest first, with ride details).
export async function POST(req: NextRequest) {
  try {
    // Who raised it comes from the token, never the body: a rider token is
    // 'user', a driver token 'driver', and the name/phone are read from that
    // account. (They used to be whatever the app sent.)
    const asDriver = requireDriverAuth(req) as any
    const asRider = asDriver?.id ? null : (requireRider(req) as any)
    if (!asDriver?.id && !asRider?.id) return withCors({ error: 'Unauthorized' }, 401)
    const b = await req.json().catch(() => ({}))
    await connectDB()
    const person: any = asDriver?.id
      ? await Driver.findById(asDriver.id).select('name phone').lean()
      : await User.findById(asRider.id).select('name phone').lean()
    if (!person) return withCors({ error: 'Account not found' }, 404)

    // A ride id is kept only when the caller is on that ride.
    let rideId: any = undefined
    if (b.rideId && mongoose.isValidObjectId(String(b.rideId))) {
      const r: any = await Ride.findById(b.rideId).select('riderId driverId').lean()
      const mine = r && (asDriver?.id ? String(r.driverId || '') === String(asDriver.id) : String(r.riderId || '') === String(asRider.id))
      if (mine) rideId = r._id
    }
    const num = (v: any, lim: number) => (typeof v === 'number' && Number.isFinite(v) && Math.abs(v) <= lim ? v : undefined)
    const alert = await SOSAlert.create({
      rideId,
      triggeredBy: asDriver?.id ? 'driver' : 'user',
      name: person.name || '',
      phone: person.phone || '',
      lat: num(b.lat, 90),
      lng: num(b.lng, 180),
      address: typeof b.address === 'string' ? b.address.slice(0, 300) : '',
      status: 'active',
    })
    return withCors({ success: true, id: alert._id })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}

export async function GET(req: NextRequest) {
  try {
    if (!requireAdmin(req)) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const alerts = await SOSAlert.find()
      .sort({ createdAt: -1 })
      .limit(200)
      .populate('rideId', 'service pickupAddress dropAddress status driverName riderName')
      .lean()
    return withCors({ alerts })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
