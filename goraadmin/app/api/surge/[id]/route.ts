import { NextRequest, NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { connectDB } from '@/lib/mongodb'
import SurgePrice from '@/models/SurgePrice'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'surge.update', String(params.id))
  await connectDB()
  const body = await req.json()
  const surge = await SurgePrice.findByIdAndUpdate(params.id, body, { new: true })
  if (!surge) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json(surge)
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'surge.delete', String(params.id))
  await connectDB()
  await SurgePrice.findByIdAndDelete(params.id)
  return NextResponse.json({ ok: true })
}
