export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import { guardAdmin } from '@/lib/admin-guard'
import { accessState, computeSettlement, zoneNameMap } from '@/lib/zone-admin'

// GET ?month=YYYY-MM — the franchise business at a glance: subscription
// income, renewals coming up, revenue share owed, and reset requests.
export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    await connectDB()
    const month = req.nextUrl.searchParams.get('month') || ''
    const [admins, names, staffResets] = await Promise.all([
      ZoneAdmin.find().select('-password').lean(),
      zoneNameMap(),
      ZoneStaff.countDocuments({ passwordResetRequestedAt: { $ne: null } }),
    ])
    const now = Date.now()
    let totalIncome = 0, monthIncome = 0
    const counts = { active: 0, grace: 0, expired: 0, blocked: 0, no_subscription: 0 } as Record<string, number>
    const rows = await Promise.all((admins as any[]).map(async a => {
      const paid = (a.payments || []).reduce((s: number, p: any) => s + (p.amount || 0), 0)
      totalIncome += paid
      const settlement = await computeSettlement(a, month)
      monthIncome += (a.payments || []).filter((p: any) => {
        const d = new Date(new Date(p.createdAt).getTime() + 5.5 * 3600e3)
        return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}` === settlement.month
      }).reduce((s: number, p: any) => s + (p.amount || 0), 0)
      const state = accessState(a)
      counts[state] = (counts[state] || 0) + 1
      const end = a.subscriptionEndAt ? new Date(a.subscriptionEndAt).getTime() : null
      return {
        _id: a._id, name: a.name, businessName: a.businessName,
        zones: (a.zoneIds || []).map((z: any) => names.get(String(z)) || '?'),
        access: state, subscriptionEndAt: a.subscriptionEndAt || null,
        daysLeft: end ? Math.ceil((end - now) / 864e5) : null,
        totalPaid: paid, settlement,
        passwordResetRequested: !!a.passwordResetRequestedAt,
      }
    }))
    const month0 = rows[0]?.settlement.month || month
    return NextResponse.json({
      month: month0,
      totals: {
        zoneAdmins: rows.length, ...counts,
        subscriptionIncomeAllTime: totalIncome, subscriptionIncomeThisMonth: monthIncome,
        shareOwed: Math.round(rows.reduce((s, r) => s + r.settlement.due, 0) * 100) / 100,
        resetRequests: rows.filter(r => r.passwordResetRequested).length + staffResets,
      },
      expiringSoon: rows.filter(r => r.daysLeft !== null && r.daysLeft >= 0 && r.daysLeft <= 30).sort((x, y) => (x.daysLeft! - y.daysLeft!)),
      rows,
    })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
