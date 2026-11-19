export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import PromoCode from '@/models/PromoCode'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'
import { ZONE_PROMO_CAPS, ZONE_PROMOS_LIVE, validZonePromo } from '@/lib/zone-features'

// Zone admins' own promo codes, valid only for rides booked in their zones
// (lib/promo checks zoneIds). Capped so one zone cannot give fares away.

export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'promos' })
  if ('denied' in g) return g.denied
  const promos = await PromoCode.find({ createdByZoneAdmin: g.admin._id }).sort({ createdAt: -1 }).lean()
  return NextResponse.json({ promos, caps: ZONE_PROMO_CAPS, live: ZONE_PROMOS_LIVE })
}

// POST { code, type, value, maxDiscount?, minOrderAmount?, maxUses?, expiryDate? }
export async function POST(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'promos', write: true })
  if ('denied' in g) return g.denied
  try {
    const b = await req.json()
    const code = String(b.code || '').trim().toUpperCase()
    if (!/^[A-Z0-9]{3,20}$/.test(code)) return NextResponse.json({ error: 'Code must be 3–20 letters or digits' }, { status: 400 })
    if (!ZONE_PROMOS_LIVE) return NextResponse.json({ error: 'Zone promo codes are coming soon.', comingSoon: true }, { status: 403 })
    // With no zone, the code would carry no zone limit at all.
    if (!g.zoneIds.length) return NextResponse.json({ error: 'You have no zone assigned yet' }, { status: 400 })
    const bad = validZonePromo(b); if (bad) return NextResponse.json({ error: bad }, { status: 400 })
    if (await PromoCode.findOne({ code })) return NextResponse.json({ error: 'This code is already taken' }, { status: 409 })
    const promo = await PromoCode.create({
      code, type: b.type === 'flat' ? 'flat' : 'percent', value: Number(b.value),
      maxDiscount: Number(b.maxDiscount) || undefined, minOrderAmount: Number(b.minOrderAmount) || 0,
      maxUses: Number(b.maxUses) || 0, expiryDate: b.expiryDate ? new Date(b.expiryDate) : undefined,
      isActive: true, zoneIds: g.zoneIds, createdByZoneAdmin: g.admin._id,
    })
    await logZoneActivity(g.admin._id, g.actor, 'promo.create', { code, type: promo.type, value: promo.value })
    return NextResponse.json({ promo }, { status: 201 })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
