export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdmin } from '@/lib/admin-audit'
import { toCsv } from '@/lib/csv'

const MAX_ROWS = 2000

// POST { status?: 'pending'|'approved'|'rejected'|'all' } → text/csv for the
// bank's bulk-payout batch. It carries FULL account numbers (the bank needs
// them), so it is behind the admin password and every export is audited with
// the row count and total. Pending is exported oldest first (the queue).
export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    const b = await req.json().catch(() => ({}))
    const status = ['pending', 'approved', 'rejected', 'all'].includes(b.status) ? b.status : 'pending'
    await connectDB()
    const q: any = status === 'all' ? {} : { status }
    const rows: any[] = await Withdrawal.find(q).sort({ createdAt: status === 'pending' ? 1 : -1 }).limit(MAX_ROWS).lean()
    const sum = rows.reduce((t, r) => t + (Number(r.amount) || 0), 0)
    const csv = toCsv(
      ['Withdrawal ID', 'Requested at (IST)', 'Driver', 'Driver phone', 'Zone', 'Amount (INR)', 'Account holder', 'Bank', 'Account number', 'IFSC', 'Status', 'UTR / payout ref', 'Processed at (IST)', 'Bank changed in last 7 days'],
      rows.map(r => [
        String(r._id), ist(r.createdAt), r.driverName || '', r.driverPhone || '', r.zoneName || '', r.amount ?? 0,
        r.accountHolderName || '', r.bankName || '', r.accountNumber || '', r.ifscCode || '', r.status || '',
        r.payoutRef || '', r.processedAt ? ist(r.processedAt) : '', r.bankChangedRecently ? 'yes' : '',
      ]),
    )
    await auditAdmin(req, requireAdmin(req), 'withdrawal.export', {
      summary: `Exported ${rows.length} ${status} withdrawal(s), ₹${Math.round(sum)} — with full account numbers`,
      details: { status, rows: rows.length, amount: Math.round(sum) },
    })
    return new NextResponse(csv, {
      status: 200,
      headers: {
        'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': `attachment; filename="gora-withdrawals-${status}-${new Date().toISOString().slice(0, 10)}.csv"`,
        'Cache-Control': 'no-store',
        'X-Row-Count': String(rows.length),
      },
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

function ist(d: any) {
  try { return new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', hour12: false }) } catch { return '' }
}
