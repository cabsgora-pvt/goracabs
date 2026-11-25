import { NextRequest, NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { connectDB } from '@/lib/mongodb'
import SurgePrice from '@/models/SurgePrice'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET() {
  await connectDB()
  const surges = await SurgePrice.find().sort({ createdAt: -1 }).lean()
  return NextResponse.json({ surges })
}

export async function POST(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'surge.create', undefined)
  await connectDB()
  const body = await req.json()
  const surge = await SurgePrice.create(body)
  return NextResponse.json(surge, { status: 201 })
}
