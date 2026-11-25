import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { softDeleteAccount } from '@/lib/account-delete'
import { pick, USER_EDITABLE, validateAccountEdit } from '@/lib/admin-account'
import { requireAdmin, bumpTokenVersion } from '@/lib/auth'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdmin } from '@/lib/admin-audit'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const user = await User.findById(params.id).lean()
    if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })
    const recentRides = await Ride.find({ riderId: params.id }).sort({ createdAt: -1 }).limit(10).lean()
    return NextResponse.json({ user, recentRides })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = pick(await req.json(), USER_EDITABLE)
    if (body.status && !['active', 'blocked'].includes(body.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    const bad = validateAccountEdit(body)
    if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    const unset: any = {}
    if ('gender' in body && body.gender === undefined) { delete body.gender; unset.gender = 1 }
    if (typeof body.phone === 'string') {
      body.phone = body.phone.replace(/\D/g, '').slice(-10)
      if (body.phone.length !== 10) return NextResponse.json({ error: 'Phone must be 10 digits' }, { status: 400 })
      if (await User.exists({ phone: body.phone, _id: { $ne: params.id } })) return NextResponse.json({ error: 'Another rider already uses this phone' }, { status: 409 })
    }
    const prev: any = mongoose.isValidObjectId(params.id) ? await User.findById(params.id).select('status').lean() : null
    if (!prev) return NextResponse.json({ error: 'User not found' }, { status: 404 })
    if (prev.status === 'deleted') return NextResponse.json({ error: 'This account was deleted', code: 'ACCOUNT_DELETED' }, { status: 409 })
    const user = await User.findOneAndUpdate({ _id: params.id, status: { $ne: 'deleted' } }, { $set: body, ...(Object.keys(unset).length ? { $unset: unset } : {}) }, { new: true, runValidators: true }).lean()
    if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })
    // Blocking ends the rider's open sessions (tokenVersion).
    if (body.status && body.status !== prev.status) {
      if (body.status === 'blocked') await bumpTokenVersion('rider', params.id)
      await auditAdmin(req, requireAdmin(req), 'user.status', { target: `user:${params.id}`, summary: `status ${prev.status} -> ${body.status}` })
    }
    return NextResponse.json(user)
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
    const del = await softDeleteAccount('rider', params.id, { requireZeroBalance: true })
    if (!del.ok) return NextResponse.json({ error: del.error }, { status: del.status })
    await auditAdmin(req, requireAdmin(req), 'user.delete', { target: `user:${params.id}`, summary: 'Soft-deleted rider account' })
    return NextResponse.json({ success: true, softDeleted: true })
  } catch {
    return NextResponse.json({ error: 'Delete failed' }, { status: 500 })
  }
}
