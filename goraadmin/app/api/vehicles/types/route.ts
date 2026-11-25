import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import VehicleType from '@/models/VehicleType'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET() {
  try {
    await connectDB()
    const types = await VehicleType.find().sort({ sortOrder: 1, createdAt: 1 }).lean()
    return NextResponse.json({ types })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'vehicle_type.create', undefined)
    await connectDB()
    const body = await req.json()
    const type = await VehicleType.create(body)
    return NextResponse.json(type, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
