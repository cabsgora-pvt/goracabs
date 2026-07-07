export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSAlert from '@/models/SOSAlert'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// POST — raise an SOS alert (called by rider or driver apps when SOS is tapped).
// GET  — admin lists alerts (newest first, with ride details).
export async function POST(req: NextRequest) {
  try {
    if (!requireAuth(req)) return withCors({ error: 'Unauthorized' }, 401)
    const b = await req.json()
    await connectDB()
    const alert = await SOSAlert.create({
      rideId: b.rideId || undefined,
      triggeredBy: b.triggeredBy === 'driver' ? 'driver' : 'user',
      name: b.name || '',
      phone: b.phone || '',
      lat: b.lat,
      lng: b.lng,
      address: b.address || '',
      status: 'active',
    })
    return withCors({ success: true, id: alert._id })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}

export async function GET(req: NextRequest) {
  try {
    if (!requireAuth(req)) return withCors({ error: 'Unauthorized' }, 401)
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
