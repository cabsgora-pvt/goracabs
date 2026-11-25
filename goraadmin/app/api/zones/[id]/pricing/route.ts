import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { guardAdmin } from '@/lib/admin-guard'
import { PRICING_FIELDS, keptAdminRef } from '@/lib/zone-features'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const zone = await Zone.findById(params.id).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ pricing: (zone as any).pricing || [] })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'zone.pricing.create', String(params.id))
    await connectDB()
    const body = await req.json()
    const zone = await Zone.findById(params.id)
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })

    const existingIdx = zone.pricing.findIndex(
      (p: any) => p.vehicleTypeName === body.vehicleTypeName && p.service === body.service
    )
    // New fares from the super admin become the reference a zone admin's
    // limit is measured from (zone-admin/pricing); unchanged fares keep it.
    const { adminRef: _ignored, ...fields } = body
    if (existingIdx >= 0) {
      const stored = zone.pricing[existingIdx].toObject()
      zone.pricing[existingIdx] = { ...stored, ...fields, adminRef: keptAdminRef(stored, fields, PRICING_FIELDS) }
    } else {
      zone.pricing.push(fields)
    }
    await zone.save()
    return NextResponse.json({ pricing: zone.pricing })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'zone.pricing.update', String(params.id))
    await connectDB()
    const { pricing } = await req.json()
    const current: any = await Zone.findById(params.id).select('pricing').lean()
    const byId = new Map<string, any>((current?.pricing || []).map((p: any) => [String(p._id), p]))
    const rows = Array.isArray(pricing)
      ? pricing.map(({ adminRef: _r, ...p }: any) => ({ ...p, adminRef: keptAdminRef(byId.get(String(p._id)), p, PRICING_FIELDS) }))
      : pricing
    const zone = await Zone.findByIdAndUpdate(params.id, { pricing: rows }, { new: true }).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ pricing: (zone as any).pricing })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
