export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/idcard → Gora Captain ID card data (+ generated Gora ID)
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    // Lazily assign a stable sequential serial number
    if (!driver.serialNo) {
      const top: any = await Driver.findOne({ serialNo: { $exists: true, $ne: null } })
        .sort({ serialNo: -1 }).select('serialNo').lean()
      driver.serialNo = ((top?.serialNo as number) || 0) + 1
      await driver.save()
    }

    const vehicleNo = (driver.vehicleRegistrationNumber || driver.vehicleNumber || '').toString()
    const prefix = vehicleNo.replace(/[^A-Za-z0-9]/g, '').slice(0, 4).toUpperCase() || 'XXXX'
    const city = (driver.zoneName || driver.state || '').toString()
    const zoneCode = city.replace(/[^A-Za-z]/g, '').slice(0, 3).toUpperCase() || 'GEN'
    const serial = String(driver.serialNo).padStart(4, '0')
    const goraId = `GC-${prefix}-${zoneCode}-${serial}`

    return withCors({
      goraId,
      name: driver.name || 'Driver',
      profilePicUrl: driver.profilePicUrl || '',
      joiningDate: driver.createdAt,
      city,
      mobile: driver.phone || '',
      vehicleNumber: vehicleNo,
      status: driver.status || 'pending',
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
