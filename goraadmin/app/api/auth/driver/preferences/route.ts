export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import RidePreference from '@/models/RidePreference'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Both POST and PATCH supported so CORS allow-method differences don't matter
async function handle(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const body = await req.json()
    await connectDB()
    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // A driver can only enable a service the admin has allowed
    if (typeof body.acceptsOutstation === 'boolean') driver.acceptsOutstation = body.acceptsOutstation && driver.allowOutstation !== false
    if (typeof body.acceptsRental === 'boolean') driver.acceptsRental = body.acceptsRental && driver.allowRental !== false
    if (typeof body.acceptsHireDriver === 'boolean') driver.acceptsHireDriver = body.acceptsHireDriver && driver.allowHireDriver !== false
    if (typeof body.acceptsDelivery === 'boolean') driver.acceptsDelivery = body.acceptsDelivery && driver.allowDelivery !== false
    // Admin-defined ride preferences (pet friendly …): only active keys stick.
    if (Array.isArray(body.ridePreferences)) {
      const keys = body.ridePreferences.map((k: any) => String(k)).slice(0, 20)
      const ok: any[] = await RidePreference.find({ key: { $in: keys }, isActive: true }).select('key').lean()
      driver.ridePreferences = ok.map(r => r.key)
    }
    await driver.save()

    return withCors({ success: true, preferences: {
      acceptsOutstation: driver.acceptsOutstation ?? false,
      acceptsRental: driver.acceptsRental ?? false,
      acceptsHireDriver: driver.acceptsHireDriver ?? false,
      acceptsDelivery: driver.acceptsDelivery ?? false,
      ridePreferences: driver.ridePreferences || [],
    } })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

export const POST = handle
export const PATCH = handle
