export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import DocumentType from '@/models/DocumentType'
import { guardAdmin } from '@/lib/admin-guard'
import { docTypeFields, publicDocType } from '@/lib/doc-types'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

// PUT  any of the POST fields (see ../route.ts) → changes just those.
// DELETE → removes the type (documents drivers already uploaded stay on them).
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'document_type.update', String(params.id))
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const b = await req.json().catch(() => ({}))
  const set = docTypeFields(b)
  await connectDB()
  const d = await DocumentType.findByIdAndUpdate(params.id, { $set: set }, { new: true, runValidators: true }).lean()
  if (!d) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ success: true, document: publicDocType(d) })
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'document_type.delete', String(params.id))
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  await DocumentType.findByIdAndDelete(params.id)
  return NextResponse.json({ success: true })
}
