export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardAdmin } from '@/lib/admin-guard'
import { computeSettlement } from '@/lib/zone-admin'

// GET — revenue share owed to the zone admin for the last six months.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const a: any = await ZoneAdmin.findById(params.id).lean()
  if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const now = new Date(Date.now() + 5.5 * 3600e3)
  const months: string[] = []
  for (let i = 0; i < 6; i++) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1))
    months.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`)
  }
  return NextResponse.json({ months: await Promise.all(months.map(m => computeSettlement(a, m))) })
}
