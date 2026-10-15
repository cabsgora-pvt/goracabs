import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import FaceVerification from '@/models/FaceVerification'
import { guardAdmin } from '@/lib/admin-guard'

// GET → this driver's face-check history (matches, mismatches, no-responses),
// newest first, for the admin to compare photo-vs-registration-signature.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const verifications = await FaceVerification.find({ driverId: params.id })
      .sort({ createdAt: -1 })
      .limit(50)
      .populate('rideId', 'pickupAddress dropAddress service')
      .lean()
    return NextResponse.json({ verifications })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
