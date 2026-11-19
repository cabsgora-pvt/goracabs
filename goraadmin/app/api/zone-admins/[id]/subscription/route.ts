export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { applyPlan, logZoneActivity, publicZoneAdmin, zoneNameMap } from '@/lib/zone-admin'

// POST { planId, paymentRef?, notes? }
// Gives the zone admin another period of a plan the super admin made.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const b = await req.json()
    await connectDB()
    const a: any = await ZoneAdmin.findById(params.id)
    if (!a) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const err = await applyPlan(a, b.planId, { paymentRef: b.paymentRef, notes: b.notes, recordedBy: requireAdmin(req)?.email })
    if (err) return NextResponse.json({ error: err }, { status: 400 })
    await a.save()
    const last = a.payments[a.payments.length - 1]
    await logZoneActivity(a._id, { type: 'super_admin', id: '', name: requireAdmin(req)?.email || 'super admin' }, 'subscription.renew',
      { plan: last.planName, amount: last.amount, until: a.subscriptionEndAt, invoice: last.invoiceNo })
    const out = a.toObject(); delete out.password
    return NextResponse.json({ zoneAdmin: publicZoneAdmin(out, await zoneNameMap()) })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
