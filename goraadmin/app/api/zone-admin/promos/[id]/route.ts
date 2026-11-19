export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import PromoCode from '@/models/PromoCode'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'

async function ownPromo(id: string, adminId: any) {
  if (!mongoose.isValidObjectId(id)) return null
  return PromoCode.findOne({ _id: id, createdByZoneAdmin: adminId })
}

// PUT { isActive } — switch one of their codes on or off.
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'promos', write: true })
  if ('denied' in g) return g.denied
  const p: any = await ownPromo(params.id, g.admin._id)
  if (!p) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const b = await req.json()
  if (b.isActive !== undefined) p.isActive = !!b.isActive
  await p.save()
  await logZoneActivity(g.admin._id, g.actor, p.isActive ? 'promo.on' : 'promo.off', { code: p.code })
  return NextResponse.json({ promo: p })
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'promos', write: true })
  if ('denied' in g) return g.denied
  const p: any = await ownPromo(params.id, g.admin._id)
  if (!p) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await p.deleteOne()
  await logZoneActivity(g.admin._id, g.actor, 'promo.delete', { code: p.code })
  return NextResponse.json({ success: true })
}
