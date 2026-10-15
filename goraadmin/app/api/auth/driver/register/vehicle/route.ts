export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
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
    // A delivery-only vehicle (Mini Truck) never gets taxi rides, and parcel
    // requests are opt-in — without this it would receive nothing at all.
    const vt: any = await VehicleType.findById(selectedVehicleTypeId).select('services').lean().catch(() => null)
    const services: string[] = vt?.services || []
    const deliveryOnly = services.includes('delivery') && !services.includes('taxi')

    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      {
        ...(deliveryOnly ? { acceptsDelivery: true } : {}),
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
