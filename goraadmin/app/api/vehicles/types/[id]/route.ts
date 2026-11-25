import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import VehicleType from '@/models/VehicleType'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'vehicle_type.update', String(params.id))
    await connectDB()
    const body = await req.json()
    const type = await VehicleType.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!type) return NextResponse.json({ error: 'Vehicle type not found' }, { status: 404 })
    return NextResponse.json(type)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'vehicle_type.delete', String(params.id))
    await connectDB()
    await VehicleType.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
