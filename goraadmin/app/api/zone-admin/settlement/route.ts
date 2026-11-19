export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { computeSettlement, guardZoneAdmin } from '@/lib/zone-admin'

// GET ?month=YYYY-MM — the zone admin's revenue share for the month, and the
// last six months, with what Gora has already paid them.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { ownerOnly: true })
  if ('denied' in g) return g.denied
  try {
    const now = new Date(Date.now() + 5.5 * 3600e3)
    const months: string[] = []
    for (let i = 0; i < 6; i++) {
      const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1))
      months.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`)
    }
    const rows = await Promise.all(months.map(m => computeSettlement(g.admin, m)))
    return NextResponse.json({
      sharePercent: g.admin.revenueSharePercent || 0,
      months: rows,
      payouts: (g.admin.payouts || []).slice().reverse().map((p: any) => ({ ...p, recordedBy: undefined })),
    })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
