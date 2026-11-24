import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
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
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = await req.json()
    const driver = await Driver.create(body)
    return NextResponse.json(driver, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
