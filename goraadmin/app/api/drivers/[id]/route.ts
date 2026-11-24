import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import DriverSubscription from '@/models/DriverSubscription'
import Withdrawal from '@/models/Withdrawal'
import { guardAdmin } from '@/lib/admin-guard'
import { pick, DRIVER_EDITABLE, validateAccountEdit } from '@/lib/admin-account'
import { requireAdmin } from '@/lib/auth'
import Zone from '@/models/Zone'
import mongoose from 'mongoose'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const driver = await Driver.findById(params.id).lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    const recentRides = await Ride.find({ driverId: params.id }).sort({ createdAt: -1 }).limit(10).lean()
    const subscriptions = await DriverSubscription.find({ driverId: params.id }).sort({ createdAt: -1 }).limit(10).lean()
    const withdrawals = await Withdrawal.find({ driverId: params.id }).sort({ createdAt: -1 }).limit(10).lean()
    return NextResponse.json({ driver, recentRides, subscriptions, withdrawals })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const raw = await req.json()
    const body = pick(raw, DRIVER_EDITABLE)
    if (body.status && !['pending', 'approved', 'blocked', 'rejected'].includes(body.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    const bad = validateAccountEdit(body)
    if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    // Gender cleared in the form: remove it rather than store an empty value.
    const unsetGender = 'gender' in body && body.gender === undefined
    if (unsetGender) delete body.gender
    if (typeof body.phone === 'string') {
      body.phone = body.phone.replace(/\D/g, '').slice(-10)
      if (body.phone.length !== 10) return NextResponse.json({ error: 'Phone must be 10 digits' }, { status: 400 })
      if (await Driver.exists({ phone: body.phone, _id: { $ne: params.id } })) return NextResponse.json({ error: 'Another driver already uses this phone' }, { status: 409 })
    }
    if (typeof body.vehicleNumber === 'string') body.vehicleRegistrationNumber = body.vehicleNumber
    // A photo the admin sets sticks: the driver's photo is otherwise put back
    // to their face-scan photo (see auth/driver/profile). The face embedding
    // used for verification is not touched.
    if (typeof body.profilePicUrl === 'string' && body.profilePicUrl) {
      const cur: any = await Driver.findById(params.id).select('faceReferencePhotoUrl').lean()
      if (cur?.faceReferencePhotoUrl) body.faceReferencePhotoUrl = body.profilePicUrl
    }
    if (typeof body.selectedVehicleTypeName === 'string') body.vehicleType = body.selectedVehicleTypeName
    const update: any = { $set: body }
    if (unsetGender) update.$unset = { gender: 1 }
    // Zone moved by the admin (manual): logged in the driver's zone history.
    if (typeof raw?.zoneId === 'string' && raw.zoneId) {
      if (!mongoose.isValidObjectId(raw.zoneId)) return NextResponse.json({ error: 'Invalid zone' }, { status: 400 })
      const [z, cur]: any[] = await Promise.all([
        Zone.findById(raw.zoneId).select('name').lean(),
        Driver.findById(params.id).select('zoneId zoneName').lean(),
      ])
      if (!z) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
      if (cur && String(cur.zoneId || '') !== String(z._id)) {
        body.zoneId = String(z._id); body.zoneName = z.name
        const admin: any = requireAdmin(req)
        update.$push = { zoneHistory: { from: cur.zoneId || '', fromName: cur.zoneName || '', to: String(z._id), toName: z.name, by: `admin:${admin?.email || 'admin'}`, at: new Date() } }
      }
    }
    const driver = await Driver.findByIdAndUpdate(params.id, update, { new: true, runValidators: true }).select('-faceSignature').lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    return NextResponse.json(driver)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    await Driver.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
