export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import VehicleType from '@/models/VehicleType'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import mongoose from 'mongoose'
import { registrationLocked, LOCKED_CODE } from '@/lib/driver-registration'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { selectedVehicleTypeId, vehicleRegistrationNumber, vehicleModel } = await req.json()
    if (!selectedVehicleTypeId || !vehicleRegistrationNumber) {
      return withCors({ error: 'Vehicle type and registration number are required' }, 400)
    }
    const plate = String(vehicleRegistrationNumber).trim().toUpperCase().slice(0, 20)
    if (!/^[A-Z0-9 -]{4,20}$/.test(plate)) return withCors({ error: 'Enter a valid registration number' }, 400)

    await connectDB()
    // The vehicle type, and its NAME (which decides the rides the driver is
    // offered), come from the VehicleType document — never from the app.
    const vt: any = mongoose.isValidObjectId(String(selectedVehicleTypeId))
      ? await VehicleType.findById(selectedVehicleTypeId).select('name services').lean()
      : null
    if (!vt?.name) return withCors({ error: 'Choose a valid vehicle type' }, 400)

    const current: any = await Driver.findById(payload.id).select('status registrationStep selectedVehicleTypeId selectedVehicleTypeName vehicleRegistrationNumber vehicleModel').lean()
    if (!current) return withCors({ error: 'Driver not found' }, 404)

    // Locked once under review / approved (lib/driver-registration.ts).
    if (registrationLocked(current)) {
      const same = String(current.selectedVehicleTypeId || '') === String(vt._id)
        && String(current.vehicleRegistrationNumber || '').trim().toUpperCase() === plate
      if (!same) {
        return withCors({ error: 'Your registration is already submitted. Contact support to change your vehicle.', code: LOCKED_CODE }, 409)
      }
      return withCors({ success: true, driver: current, unchanged: true })
    }

    // A delivery-only vehicle (Mini Truck) never gets taxi rides, and parcel
    // requests are opt-in — without this it would receive nothing at all.
    const services: string[] = vt?.services || []
    const deliveryOnly = services.includes('delivery') && !services.includes('taxi')

    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      {
        ...(deliveryOnly ? { acceptsDelivery: true } : {}),
        selectedVehicleTypeId: String(vt._id),
        selectedVehicleTypeName: vt.name,
        vehicleRegistrationNumber: plate,
        vehicleModel: typeof vehicleModel === 'string' ? vehicleModel.trim().slice(0, 60) : undefined,
        vehicleNumber: plate,
        vehicleType: vt.name,
        registrationStep: 'documents',
      },
      { new: true }
    ).select('-faceSignature -walletRechargeRefs').lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, driver })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
