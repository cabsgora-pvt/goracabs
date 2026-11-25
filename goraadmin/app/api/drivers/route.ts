import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'
import { pick, validateAccountEdit } from '@/lib/admin-account'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'

// Fields an admin may set when creating a driver by hand. Everything else in
// the body (walletBalance, status, referral and face fields, tokenVersion …)
// is ignored: a new driver always starts pending and goes through approval.
const DRIVER_CREATE = ['name', 'email', 'phone', 'gender', 'state', 'vehicleModel', 'vehicleNumber', 'selectedVehicleTypeName', 'vehicleType']

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const { searchParams } = new URL(req.url)
    const { page, limit, skip } = parsePaging(searchParams)
    const search = escapeRegex((searchParams.get('search') || '').trim())
    const status = searchParams.get('status') || ''

    const query: any = {}
    if (status && status !== 'all') query.status = status
    else query.status = { $ne: 'deleted' }
    // Dashboard links: ?filter=held (on hold / failed face check), ?filter=negative (wallet below 0)
    const filter = searchParams.get('filter') || ''
    if (filter === 'held') query.$and = [{ $or: [{ 'accountHold.active': true }, { faceVerificationRequired: true }] }]
    if (filter === 'negative') query.walletBalance = { $lt: 0 }
    if (search) {
      query.$or = [
        { name: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } },
        { vehicleNumber: { $regex: search, $options: 'i' } },
      ]
    }

    const total = await Driver.countDocuments(query)
    const drivers = await Driver.find(query)
      .select('-faceSignature -bankDetails -bankAccounts -walletRechargeRefs -documents')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean()

    return NextResponse.json({ drivers, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = pick(await req.json().catch(() => ({})), DRIVER_CREATE)
    const bad = validateAccountEdit(body)
    if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    if (body.gender === undefined) delete body.gender
    const phone = String(body.phone || '').replace(/\D/g, '').slice(-10)
    if (phone.length !== 10) return NextResponse.json({ error: 'Phone must be 10 digits' }, { status: 400 })
    if (await Driver.exists({ phone })) return NextResponse.json({ error: 'A driver already uses this phone' }, { status: 409 })
    const driver: any = await Driver.create({ ...body, phone, status: 'pending', registrationStep: 'otp', walletBalance: 0 })
    await auditAdmin(req, requireAdmin(req), 'driver.create', { target: `driver:${driver._id}`, summary: `Created driver ${body.name || ''} ${phone.slice(-4)}` })
    const out = driver.toObject(); delete out.faceSignature
    return NextResponse.json(out, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
