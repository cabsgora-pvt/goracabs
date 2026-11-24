import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { pick, USER_EDITABLE, validateAccountEdit } from '@/lib/admin-account'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
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
    const denied = guardAdmin(req); if (denied) return denied
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
    const user = await User.findByIdAndUpdate(params.id, { $set: body, ...(Object.keys(unset).length ? { $unset: unset } : {}) }, { new: true, runValidators: true }).lean()
    if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })
    return NextResponse.json(user)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    await User.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
