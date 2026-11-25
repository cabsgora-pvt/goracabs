export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardAdmin } from '@/lib/admin-guard'
import { invoiceFor } from '@/lib/zone-admin'

// GET — invoice for one subscription payment.
export async function GET(req: NextRequest, { params }: { params: { id: string; pid: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const a: any = await ZoneAdmin.findById(params.id).lean()
  const inv = a && await invoiceFor(a, params.pid)
  if (!inv) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ invoice: inv })
}
