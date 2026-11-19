export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { guardZoneAdmin, invoiceFor } from '@/lib/zone-admin'

// GET — invoice for one of the zone admin's own subscription payments.
export async function GET(req: NextRequest, { params }: { params: { pid: string } }) {
  const g = await guardZoneAdmin(req, { ownerOnly: true })
  if ('denied' in g) return g.denied
  const inv = await invoiceFor(g.admin, params.pid)
  if (!inv) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ invoice: inv })
}
