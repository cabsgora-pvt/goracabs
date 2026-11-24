export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Admin ride list — carries rider phones and ride OTPs, so admin only.
export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const { searchParams } = new URL(req.url)
    const { page, limit, skip } = parsePaging(searchParams)
    const status = searchParams.get('status') || ''
    const service = searchParams.get('service') || ''
    const dateFrom = searchParams.get('dateFrom') || ''
    const dateTo = searchParams.get('dateTo') || ''
    const search = escapeRegex((searchParams.get('search') || '').trim())

    const query: any = {}
    if (status && status !== 'all') query.status = status
    if (service && service !== 'all') query.service = service
    if (dateFrom || dateTo) {
      query.createdAt = {}
      if (dateFrom) query.createdAt.$gte = new Date(dateFrom)
      if (dateTo) {
        const to = new Date(dateTo)
        to.setHours(23, 59, 59, 999)
        query.createdAt.$lte = to
      }
    }
    if (search) {
      query.$or = [
        { riderName: { $regex: search, $options: 'i' } },
        { driverName: { $regex: search, $options: 'i' } },
      ]
    }

    const total = await Ride.countDocuments(query)
    const rides = await Ride.find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .lean()

    return NextResponse.json({ rides, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
