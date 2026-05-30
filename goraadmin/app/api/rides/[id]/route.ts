export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'

// GET ride by id — also returns hydrated driver + rider sub-objects
// (driver photo, plate, model, rating; rider photo) so both apps can render rich cards.
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })

    if (ride.driverId) {
      const d: any = await Driver.findById(ride.driverId)
        .select('name phone profilePicUrl vehicleModel vehicleNumber vehicleRegistrationNumber rating currentLat currentLng currentHeading locationUpdatedAt')
        .lean()
      if (d) ride.driver = {
        id: d._id,
        name: d.name,
        phone: d.phone,
        profilePicUrl: d.profilePicUrl,
        vehicleModel: d.vehicleModel,
        vehicleNumber: d.vehicleNumber || d.vehicleRegistrationNumber,
        rating: d.rating,
        currentLat: d.currentLat,
        currentLng: d.currentLng,
        currentHeading: d.currentHeading,
        locationUpdatedAt: d.locationUpdatedAt,
      }
    }

    if (ride.riderId) {
      const u: any = await User.findById(ride.riderId).select('name phone profilePicUrl').lean()
      if (u) ride.rider = {
        id: u._id,
        name: u.name,
        phone: u.phone,
        profilePicUrl: u.profilePicUrl,
      }
    }

    return NextResponse.json(ride)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
