export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Zone from '@/models/Zone'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'
import { PRICING_FIELDS, RENTAL_FIELDS } from '@/lib/zone-features'

// Fares a zone admin may set for their own zones. Commission %, GST and
// switching a service on or off stay with the super admin: commission is the
// super admin's own earning and GST is a tax setting.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'pricing' })
  if ('denied' in g) return g.denied
  try {
    const zones = await Zone.find({ _id: { $in: g.zoneIds } })
      .select('name city isActive pricing rentalPackages').lean()
    return NextResponse.json({
      zones,
      editable: { pricing: PRICING_FIELDS, rental: RENTAL_FIELDS },
      limitPct: g.admin.priceChangeLimitPct ?? 30,
    })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

/**
 * True when [next] is outside ±limitPct% of the super admin's value [ref].
 * A limit of 0 means no limit. A field the super admin left at 0 stays 0:
 * a band around 0 is no band, and a charge Gora never set is not the zone
 * admin's to invent.
 */
function outOfBand(ref: number, next: number, limitPct: number) {
  if (!limitPct) return false
  if (!ref) return next !== 0
  const lo = ref * (1 - limitPct / 100), hi = ref * (1 + limitPct / 100)
  return next < lo - 1e-9 || next > hi + 1e-9
}

// PUT { zoneId, kind: 'pricing' | 'rental', rowId, values: { field: number } }
export async function PUT(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'pricing', write: true })
  if ('denied' in g) return g.denied
  try {
    const b = await req.json()
    const zoneId = String(b.zoneId || '')
    // Only their own zone, whatever id is sent.
    if (!g.zoneIds.includes(zoneId)) return NextResponse.json({ error: 'Not your zone' }, { status: 403 })
    if (!mongoose.isValidObjectId(b.rowId)) return NextResponse.json({ error: 'Row not found' }, { status: 404 })
    const kind = b.kind === 'rental' ? 'rental' : 'pricing'
    const arr = kind === 'rental' ? 'rentalPackages' : 'pricing'
    const allowed: readonly string[] = kind === 'rental' ? RENTAL_FIELDS : PRICING_FIELDS
    const values = b.values && typeof b.values === 'object' ? b.values : {}

    const zone: any = await Zone.findOne({ _id: zoneId, [`${arr}._id`]: b.rowId })
    if (!zone) return NextResponse.json({ error: 'Row not found' }, { status: 404 })
    const row: any = zone[arr].id(b.rowId)

    // The super admin's fares, taken the first time a zone admin edits this
    // row (and again after the super admin saves it — see the zone pricing
    // routes, which clear it). The limit is measured from these.
    const ref: Record<string, number> = row.adminRef && typeof row.adminRef === 'object'
      ? row.adminRef
      : Object.fromEntries(allowed.map(k => [k, Number(row[k]) || 0]))
    const limitPct = Number(g.admin.priceChangeLimitPct ?? 30)

    const changes: Record<string, { from: number; to: number }> = {}
    for (const [k, v] of Object.entries(values)) {
      if (!allowed.includes(k)) continue
      const n = Number(v)
      if (!Number.isFinite(n) || n < 0 || n > 1_000_000) {
        return NextResponse.json({ error: `Invalid value for ${k}` }, { status: 400 })
      }
      if (k === 'emptyReturnPercent' && n > 100) return NextResponse.json({ error: 'Empty return % cannot exceed 100' }, { status: 400 })
      if (outOfBand(Number(ref[k]) || 0, n, limitPct)) {
        const r = Number(ref[k]) || 0
        if (!r) return NextResponse.json({ error: `${k} is not set by Gora for this vehicle, so it stays 0. Ask Gora to set it first.`, field: k }, { status: 400 })
        return NextResponse.json({
          error: `${k} must stay within ±${limitPct}% of ₹${r} (₹${Math.round(r * (1 - limitPct / 100) * 100) / 100}–₹${Math.round(r * (1 + limitPct / 100) * 100) / 100}). Ask Gora to change it beyond that.`,
          field: k,
        }, { status: 400 })
      }
      const from = Number(row[k]) || 0
      if (from !== n) { changes[k] = { from, to: n }; row[k] = n }
    }
    if (!Object.keys(changes).length) return NextResponse.json({ error: 'Nothing to update' }, { status: 400 })
    if (!row.adminRef) row.adminRef = ref
    zone.markModified(arr)
    await zone.save()

    await logZoneActivity(g.admin._id, g.actor, 'pricing.update', {
      zone: zone.name, kind, vehicle: row.vehicleTypeName, service: row.service || 'rental', changes,
    })
    const out = await Zone.findById(zoneId).select('name city isActive pricing rentalPackages').lean()
    return NextResponse.json({ zone: out })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
