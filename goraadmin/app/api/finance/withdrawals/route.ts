export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// GET ?status=pending|approved|rejected|all &q=<driver name / phone> &page&limit
// The list never carries a full account number (accountLast4 only); the full
// details for paying are behind the password (POST withdrawals/bank, export).
// Pending is the queue: oldest first. `totals` are per status over ALL
// matching requests (count + amount), not just this page.
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp)
    const status = sp.get('status') || ''
    const q = escapeRegex((sp.get('q') || '').trim())

    const base: any = {}
    if (q) base.$or = [{ driverName: { $regex: q, $options: 'i' } }, { driverPhone: { $regex: q } }]
    const query: any = { ...base }
    if (['pending', 'approved', 'rejected'].includes(status)) query.status = status

    const [total, rows, byStatus] = await Promise.all([
      Withdrawal.countDocuments(query),
      Withdrawal.find(query)
        .select('-accountNumber')
        .sort({ createdAt: status === 'pending' ? 1 : -1, _id: 1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      Withdrawal.aggregate([{ $match: base }, { $group: { _id: '$status', count: { $sum: 1 }, amount: { $sum: { $ifNull: ['$amount', 0] } } } }]),
    ])
    // Last 4 for the list, read separately so the full number never enters it.
    const last4 = new Map<string, string>(
      (await Withdrawal.find({ _id: { $in: rows.map((r: any) => r._id) } }).select('accountNumber').lean())
        .map((r: any) => [String(r._id), String(r.accountNumber || '').replace(/\s/g, '').slice(-4)]),
    )
    const withdrawals = rows.map((r: any) => ({ ...r, accountLast4: last4.get(String(r._id)) || '' }))
    const totals: Record<string, { count: number; amount: number }> = {
      pending: { count: 0, amount: 0 }, approved: { count: 0, amount: 0 }, rejected: { count: 0, amount: 0 },
    }
    for (const b of byStatus) if (b._id) totals[b._id] = { count: b.count, amount: Math.round(b.amount * 100) / 100 }

    return NextResponse.json({ withdrawals, total, page, limit, totals })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
