import { NextRequest, NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { connectDB } from '@/lib/mongodb'
import SurgePrice from '@/models/SurgePrice'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  await connectDB()
  const body = await req.json()
  const surge = await SurgePrice.findByIdAndUpdate(params.id, body, { new: true })
  if (!surge) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json(surge)
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  await connectDB()
  await SurgePrice.findByIdAndDelete(params.id)
  return NextResponse.json({ ok: true })
}
