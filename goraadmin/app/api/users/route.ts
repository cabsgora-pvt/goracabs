import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'
import { pick, validateAccountEdit } from '@/lib/admin-account'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'

// Fields an admin may set when creating a rider by hand; walletBalance,
// referral counters, tokenVersion etc. in the body are ignored.
const USER_CREATE = ['name', 'email', 'phone', 'city', 'gender']

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
    if (searchParams.get('filter') === 'held') query['accountHold.active'] = true
    if (search) {
      query.$or = [
        { name: { $regex: search, $options: 'i' } },
        { email: { $regex: search, $options: 'i' } },
        { phone: { $regex: search, $options: 'i' } },
      ]
    }

    const total = await User.countDocuments(query)
    const users = await User.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean()

    return NextResponse.json({ users, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const raw = await req.json().catch(() => ({}))
    const body = pick(raw, USER_CREATE)
    const bad = validateAccountEdit(body)
    if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    if (body.gender === undefined) delete body.gender
    const phone = String(body.phone || '').replace(/\D/g, '').slice(-10)
    if (phone.length !== 10) return NextResponse.json({ error: 'Phone must be 10 digits' }, { status: 400 })
    if (await User.exists({ phone })) return NextResponse.json({ error: 'A rider already uses this phone' }, { status: 409 })
    const status = raw?.status === 'blocked' ? 'blocked' : 'active'
    const user: any = await User.create({ ...body, phone, status, walletBalance: 0 })
    await auditAdmin(req, requireAdmin(req), 'user.create', { target: `user:${user._id}`, summary: `Created rider ${body.name || ''} ${phone.slice(-4)}` })
    return NextResponse.json(user, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
