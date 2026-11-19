export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdminActivity from '@/models/ZoneAdminActivity'
import { guardAdmin } from '@/lib/admin-guard'

// GET ?page= — the zone admin's activity log, newest first.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const page = Math.max(1, parseInt(req.nextUrl.searchParams.get('page') || '1', 10) || 1)
  const limit = 30
  const q = { zoneAdminId: params.id }
  const [items, total] = await Promise.all([
    ZoneAdminActivity.find(q).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).lean(),
    ZoneAdminActivity.countDocuments(q),
  ])
  return NextResponse.json({ items, total, page, pages: Math.max(1, Math.ceil(total / limit)) })
}
