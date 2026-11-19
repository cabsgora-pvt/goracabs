export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import Zone from '@/models/Zone'
import { guardZoneAdmin, publicZoneAdmin, zoneNameMap } from '@/lib/zone-admin'

export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req)
  if ('denied' in g) return g.denied
  const me: any = publicZoneAdmin(g.admin, await zoneNameMap())
  // Their own payment history is theirs to see; who recorded it is not.
  me.payments = me.payments.map((p: any) => ({ ...p, recordedBy: undefined }))
  me.payouts = me.payouts.map((p: any) => ({ ...p, recordedBy: undefined }))
  const zones: any[] = await Zone.find({ _id: { $in: g.zoneIds } }).select('name supportPhone').lean()
  me.zones = zones.map(z => ({ _id: String(z._id), name: z.name, supportPhone: z.supportPhone || '' }))
  return NextResponse.json({
    zoneAdmin: me,
    session: {
      features: g.features, isOwner: g.isOwner, readOnly: g.readOnly,
      actor: g.actor, impersonatedBy: g.impersonatedBy || null,
    },
  })
}
