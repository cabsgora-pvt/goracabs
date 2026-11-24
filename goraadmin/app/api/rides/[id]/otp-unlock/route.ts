export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { newRideOtp } from '@/lib/ride-otp'

// POST /api/rides/{id}/otp-unlock  body: { which?: 'otp' | 'dropOtp' | 'both' (default 'both') }
// Admin only. Clears a ride-OTP lock (5 wrong codes, lib/ride-otp.ts) and
// issues a FRESH code, so whatever was learned from the failed guesses is
// worthless. The rider (or parcel receiver) sees the new code on GET /rides/:id.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    const b = await req.json().catch(() => ({}))
    const which = ['otp', 'dropOtp'].includes(b?.which) ? b.which : 'both'
    await connectDB()
    const set: any = {}
    if (which !== 'dropOtp') Object.assign(set, { otp: newRideOtp(), otpAttempts: 0, otpLocked: false })
    if (which !== 'otp') Object.assign(set, { dropOtpAttempts: 0, dropOtpLocked: false })
    // Only a parcel has a drop OTP; give it a fresh one too.
    const cur: any = await Ride.findById(params.id).select('service dropOtp status').lean()
    if (!cur) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
    if (['completed', 'cancelled'].includes(cur.status)) return NextResponse.json({ error: `Ride is ${cur.status}` }, { status: 409 })
    if (which !== 'otp' && cur.dropOtp) set.dropOtp = newRideOtp()
    await Ride.updateOne({ _id: params.id }, { $set: set })
    return NextResponse.json({ success: true, unlocked: which })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
