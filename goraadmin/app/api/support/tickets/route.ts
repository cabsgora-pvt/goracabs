import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const { searchParams } = new URL(req.url)
    // NaN-safe, capped at 200 (it took any ?limit= the caller sent).
    const { page, limit } = parsePaging(searchParams)
    const status = searchParams.get('status') || ''

    const query: any = {}
    if (status && status !== 'all') query.status = status

    const total = await SupportTicket.countDocuments(query)
    const tickets = await SupportTicket.find(query)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean()

    return NextResponse.json({ tickets, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = await req.json()
    const ticket = await SupportTicket.create(body)
    return NextResponse.json(ticket, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
