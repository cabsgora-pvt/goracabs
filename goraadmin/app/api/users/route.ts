import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
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
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = await req.json()
    const user = await User.create(body)
    return NextResponse.json(user, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
