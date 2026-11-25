export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import bcrypt from 'bcryptjs'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import ZoneStaff from '@/models/ZoneStaff'
import PromoCode from '@/models/PromoCode'
import { guardAdmin } from '@/lib/admin-guard'
import { logZoneActivity, publicZoneAdmin, zoneNameMap, zonesTakenByOthers } from '@/lib/zone-admin'
import { requireAdmin } from '@/lib/auth'
import { cleanFeatures } from '@/lib/zone-features'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    const a: any = await ZoneAdmin.findById(params.id).select('-password').lean()
    if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const ids = (a.zoneIds || []).map(String)
    const [names, rides, completed, drivers] = await Promise.all([
      zoneNameMap(),
      Ride.countDocuments({ zoneId: { $in: a.zoneIds || [] } }),
      Ride.aggregate([
        { $match: { zoneId: { $in: a.zoneIds || [] }, status: 'completed' } },
        { $group: { _id: null, n: { $sum: 1 }, fare: { $sum: { $ifNull: ['$totalFare', 0] } }, commission: { $sum: { $ifNull: ['$commissionAmount', 0] } } } },
      ]),
      Driver.countDocuments({ zoneId: { $in: ids } }),
    ])
    return NextResponse.json({
      zoneAdmin: publicZoneAdmin(a, names),
      stats: {
        rides, drivers,
        completedRides: completed[0]?.n || 0,
        revenue: completed[0]?.fare || 0,
        commission: completed[0]?.commission || 0,
      },
    })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

// PUT { name?, phone?, businessName?, address?, gstNumber?, zoneIds?, status?, password?,
//       features?, revenueSharePercent?, priceChangeLimitPct? }
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    const b = await req.json()
    const set: any = {}
    for (const k of ['name', 'phone', 'businessName', 'address', 'gstNumber']) if (b[k] !== undefined) set[k] = b[k]
    if (b.status !== undefined) {
      if (!['active', 'blocked'].includes(b.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
      set.status = b.status
    }
    if (Array.isArray(b.zoneIds)) {
      const zoneIds = b.zoneIds.map(String)
      const { taken } = await zonesTakenByOthers(zoneIds, params.id)
      if (taken.length) {
        return NextResponse.json({ error: 'One of these zones already has a zone admin. Remove it from them first.' }, { status: 409 })
      }
      set.zoneIds = zoneIds
    }
    if (b.password) {
      if (String(b.password).length < 8) return NextResponse.json({ error: 'Password must be at least 8 characters' }, { status: 400 })
      set.password = await bcrypt.hash(String(b.password), 10)
      set.passwordResetRequestedAt = null
    }
    if (b.features !== undefined) set.features = cleanFeatures(b.features)
    if (b.revenueSharePercent !== undefined) {
      const v = Number(b.revenueSharePercent)
      if (!(v >= 0 && v <= 100)) return NextResponse.json({ error: 'Revenue share must be 0–100%' }, { status: 400 })
      set.revenueSharePercent = v
    }
    if (b.priceChangeLimitPct !== undefined) {
      const v = Number(b.priceChangeLimitPct)
      if (!(v >= 0 && v <= 1000)) return NextResponse.json({ error: 'Price limit must be 0–1000%' }, { status: 400 })
      set.priceChangeLimitPct = v
    }
    const a: any = await ZoneAdmin.findByIdAndUpdate(params.id, { $set: set }, { new: true }).select('-password').lean()
    if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const { password: _p, ...logged } = set
    await logZoneActivity(a._id, { type: 'super_admin', id: '', name: requireAdmin(req)?.email || 'super admin' }, 'admin.update',
      { ...logged, ...(b.password ? { password: 'reset' } : {}) })
    return NextResponse.json({ zoneAdmin: publicZoneAdmin(a, await zoneNameMap()) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    await ZoneAdmin.findByIdAndDelete(params.id)
    // Nothing of theirs keeps working after them: their zone promo codes are
    // switched off and their staff logins removed.
    await PromoCode.updateMany({ createdByZoneAdmin: params.id }, { $set: { isActive: false } })
    await ZoneStaff.deleteMany({ zoneAdminId: params.id })
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
