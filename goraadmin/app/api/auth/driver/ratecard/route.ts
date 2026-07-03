export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/ratecard → the driver's zone fare cards (per vehicle type)
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const driver: any = await Driver.findById(payload.id).select('zoneId zoneName').lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    let cards: any[] = []
    if (driver.zoneId) {
      const zone: any = await Zone.findById(driver.zoneId).lean()
      if (zone?.pricing) {
        cards = zone.pricing
          .filter((p: any) => p.service === 'taxi' && p.isActive !== false)
          .map((p: any) => ({
            vehicleType: p.vehicleTypeName || 'Vehicle',
            baseFare: p.baseFare || 0,
            perKm: p.perKm || 0,
            perMin: p.perMin || 0,
            minFare: p.minFare || 0,
          }))
      }
    }

    return withCors({ zone: driver.zoneName || '', cards })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
