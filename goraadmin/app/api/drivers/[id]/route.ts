import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import DriverSubscription from '@/models/DriverSubscription'
import Withdrawal from '@/models/Withdrawal'
import { guardAdmin } from '@/lib/admin-guard'
import { softDeleteAccount } from '@/lib/account-delete'
import { pick, DRIVER_EDITABLE, validateAccountEdit } from '@/lib/admin-account'
import { requireAdmin, bumpTokenVersion } from '@/lib/auth'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdmin } from '@/lib/admin-audit'
import { approvalBlocker } from '@/lib/driver-approval'
import Zone from '@/models/Zone'
import mongoose from 'mongoose'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
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
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const raw = await req.json()
    const body = pick(raw, DRIVER_EDITABLE)
    if (body.status && !['pending', 'approved', 'blocked', 'rejected'].includes(body.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    const bad = validateAccountEdit(body)
    if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    // Bank details are where payouts go: changing them needs the password.
    const bankKeys = Object.keys(body).filter(k => k.startsWith('bankDetails.'))
    if (bankKeys.length) { const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd }
    const prev: any = mongoose.isValidObjectId(params.id)
      ? await Driver.findById(params.id).select('status registrationStep documents selectedVehicleTypeName vehicleType name').lean() : null
    if (!prev) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    // A deleted account stays deleted: no status (e.g. 'approved') or other edit.
    if (prev.status === 'deleted') return NextResponse.json({ error: 'This driver account was deleted', code: 'DRIVER_DELETED' }, { status: 409 })
    // Approving from pending/rejected goes through the same checks as /approve;
    // blocked -> approved (unblock) is allowed as before.
    if (body.status === 'approved' && prev.status !== 'approved' && prev.status !== 'blocked') {
      // judged on the state this edit leaves (it may also set the step / vehicle)
      const chk = await approvalBlocker({ ...prev, ...pick(body, ['registrationStep', 'selectedVehicleTypeName', 'vehicleType']) })
      if (!chk.ok) return NextResponse.json({ error: chk.error, code: chk.code, missing: chk.missing }, { status: chk.status })
    }
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
    const driver = await Driver.findOneAndUpdate({ _id: params.id, status: { $ne: 'deleted' } }, update, { new: true, runValidators: true }).select('-faceSignature').lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    // Blocking ends the driver's open sessions (tokenVersion).
    if (body.status === 'blocked' && prev.status !== 'blocked') await bumpTokenVersion('driver', params.id)
    if (bankKeys.length || (body.status && body.status !== prev.status)) {
      await auditAdmin(req, requireAdmin(req), bankKeys.length ? 'driver.bank.update' : 'driver.status', {
        target: `driver:${params.id}`,
        summary: [body.status && body.status !== prev.status ? `status ${prev.status} -> ${body.status}` : '', bankKeys.length ? `bank fields: ${bankKeys.map(k => k.slice(12)).join(', ')}` : ''].filter(Boolean).join('; '),
      })
    }
    return NextResponse.json(driver)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    // Soft delete only (lib/account-delete): history stays, PII is blanked,
    // refused during a live ride or with money in the wallet.
    const del = await softDeleteAccount('driver', params.id, { requireZeroBalance: true })
    if (!del.ok) return NextResponse.json({ error: del.error }, { status: del.status })
    await auditAdmin(req, requireAdmin(req), 'driver.delete', { target: `driver:${params.id}`, summary: 'Soft-deleted driver account' })
    return NextResponse.json({ success: true, softDeleted: true })
  } catch {
    return NextResponse.json({ error: 'Delete failed' }, { status: 500 })
  }
}
