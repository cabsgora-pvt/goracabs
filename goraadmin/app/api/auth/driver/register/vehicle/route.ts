export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { selectedVehicleTypeId, selectedVehicleTypeName, vehicleRegistrationNumber, vehicleModel } = await req.json()
    if (!selectedVehicleTypeId || !vehicleRegistrationNumber) {
      return withCors({ error: 'Vehicle type and registration number are required' }, 400)
    }

    await connectDB()
    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      {
        selectedVehicleTypeId,
        selectedVehicleTypeName,
        vehicleRegistrationNumber,
        vehicleModel,
        vehicleNumber: vehicleRegistrationNumber,
        vehicleType: selectedVehicleTypeName,
        registrationStep: 'documents',
      },
      { new: true }
    ).lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, driver })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
