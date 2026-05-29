export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { isOnline, lat, lng } = await req.json()
    await connectDB()

    const update: any = { isOnline: !!isOnline }
    if (lat != null) update.currentLat = lat
    if (lng != null) update.currentLng = lng

    const driver: any = await Driver.findByIdAndUpdate(payload.id, update, { new: true }).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    return withCors({ success: true, isOnline: driver.isOnline })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
