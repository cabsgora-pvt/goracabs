export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { logZoneActivity, publicZoneAdmin, zoneNameMap } from '@/lib/zone-admin'

// POST { month: 'YYYY-MM', amount, paymentRef?, notes? }
// Records a revenue-share payment the super admin made to the zone admin
// (outside the app — bank/UPI). Nothing is moved by this; it is the record.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const b = await req.json()
    if (!/^\d{4}-\d{2}$/.test(String(b.month || ''))) return NextResponse.json({ error: 'Choose the month' }, { status: 400 })
    const amount = Number(b.amount)
    if (!(amount > 0) || !Number.isFinite(amount)) return NextResponse.json({ error: 'Enter the amount paid' }, { status: 400 })
    await connectDB()
    const a: any = await ZoneAdmin.findById(params.id)
    if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const by = requireAdmin(req)?.email
    a.payouts.push({ month: b.month, amount, paymentRef: b.paymentRef, notes: b.notes, recordedBy: by })
    await a.save()
    await logZoneActivity(a._id, { type: 'super_admin', id: '', name: by || 'super admin' }, 'payout.record', { month: b.month, amount, paymentRef: b.paymentRef })
    const out = a.toObject(); delete out.password
    return NextResponse.json({ zoneAdmin: publicZoneAdmin(out, await zoneNameMap()) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
