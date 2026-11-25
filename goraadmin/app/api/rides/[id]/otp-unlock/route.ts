export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { newRideOtp } from '@/lib/ride-otp'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody, auditAdmin } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

// POST /api/rides/{id}/otp-unlock  body: { which?: 'otp' | 'dropOtp' | 'both' (default 'both') }
// Admin only. Clears a ride-OTP lock (5 wrong codes, lib/ride-otp.ts) and
// issues a FRESH code, so whatever was learned from the failed guesses is
// worthless. The rider (or parcel receiver) sees the new code on GET /rides/:id.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'ride.otp_unlock', String(params.id))
  try {
    const b = await req.json().catch(() => ({}))
    if (b?.action === 'verbal_confirm') return verbalConfirm(req, params.id, b)
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

// POST /api/rides/{id}/otp-unlock  { action: 'verbal_confirm', note }
// Admin only (same guards as above). When the receiver cannot read out the
// drop OTP (no phone, locked code) support confirms the handover by phone
// instead: the parcel is marked delivered — the same fields the driver's
// 'deliver' writes, COD included — with deliveryVerbalConfirm { by: <admin
// email>, adminId, note, at } on the ride and an audit row. Only for a parcel
// that is under way (ongoing, collected / in transit). A note (5..300 chars)
// saying who confirmed is required.
async function verbalConfirm(req: NextRequest, id: string, b: any) {
  const admin: any = requireAdmin(req)
  const note = typeof b?.note === 'string' ? b.note.trim() : ''
  if (note.length < 5 || note.length > 300) {
    return NextResponse.json({ error: 'Say who confirmed the handover and how (5–300 characters)', code: 'NOTE_REQUIRED' }, { status: 400 })
  }
  await connectDB()
  const ride: any = await Ride.findById(id).select('service status deliveryPhase fare tip codAmount paymentMode driverId').lean()
  if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
  if (ride.service !== 'delivery') return NextResponse.json({ error: 'Not a delivery', code: 'NOT_DELIVERY' }, { status: 400 })
  const now = new Date()
  const set: any = {
    deliveryPhase: 'delivered', deliveredAt: now,
    deliveryFinalFare: Math.round(ride.fare || 0),
    codCollected: Math.max(0, Math.round(ride.codAmount || 0)),
    deliveryVerbalConfirm: { by: String(admin?.email || ''), adminId: String(admin?.id || ''), note, at: now },
  }
  set.totalFare = set.deliveryFinalFare + (ride.tip || 0)
  if (ride.paymentMode === 'online' || ride.paymentMode === 'wallet') { set.awaitingPayment = true; set.paymentStatus = 'pending' }
  const done: any = await Ride.findOneAndUpdate(
    { _id: id, service: 'delivery', status: 'ongoing', deliveryPhase: { $in: ['collected', 'in_transit'] } },
    { $set: set },
    { new: true },
  ).select('deliveryPhase status codCollected totalFare').lean()
  if (!done) {
    return NextResponse.json({ error: `Only a parcel on its way can be confirmed (status ${ride.status}, phase ${ride.deliveryPhase || 'pending'})`, code: 'DELIVERY_NOT_IN_TRANSIT' }, { status: 409 })
  }
  await auditAdmin(req, admin, 'ride.delivery.verbal_confirm', { target: `ride:${id}`, summary: `Parcel marked delivered by verbal confirmation: ${note}`.slice(0, 300), details: { note } })
  return NextResponse.json({ success: true, deliveryPhase: done.deliveryPhase, status: done.status, codCollected: done.codCollected, totalFare: done.totalFare, verbalConfirm: set.deliveryVerbalConfirm })
}
