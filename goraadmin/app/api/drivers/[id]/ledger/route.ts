export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Transaction from '@/models/Transaction'
import WalletTransaction from '@/models/WalletTransaction'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

// GET /api/drivers/[id]/ledger?page&limit — every wallet movement of this
// driver, newest first: driver Transactions (earnings, commission, recharges,
// withdrawals, admin adjustments …) plus any WalletTransaction rows filed under
// the same id. Amounts are signed (+ credit / − debit) and carry balanceAfter.
// Paged across both collections: the top (skip + limit) of each is merged.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    await connectDB()
    const { page, limit, skip } = parsePaging(req.nextUrl.searchParams, 25)
    const id = new mongoose.Types.ObjectId(params.id)
    const take = skip + limit
    const [tx, wtx, nTx, nWtx] = await Promise.all([
      Transaction.find({ driverId: id }).sort({ createdAt: -1, _id: -1 }).limit(take).lean(),
      WalletTransaction.find({ userId: id }).sort({ createdAt: -1, _id: -1 }).limit(take).lean(),
      Transaction.countDocuments({ driverId: id }),
      WalletTransaction.countDocuments({ userId: id }),
    ])
    const rows = [
      ...tx.map((t: any) => ({ _id: String(t._id), source: 'transaction', at: t.createdAt, type: t.type, amount: Number(t.amount) || 0,
        balanceAfter: t.balanceAfter, description: t.description || '', rideId: t.rideId ? String(t.rideId) : '', paymentMode: t.paymentMode || '' })),
      ...wtx.map((w: any) => ({ _id: String(w._id), source: 'wallet', at: w.createdAt, type: `${w.source || 'wallet'}_${w.type}`,
        amount: w.type === 'debit' ? -Math.abs(Number(w.amount) || 0) : Math.abs(Number(w.amount) || 0),
        balanceAfter: w.balanceAfter, description: w.note || '', rideId: '', paymentMode: '' })),
    ].sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime() || (a._id < b._id ? 1 : -1))
    return NextResponse.json({ rows: rows.slice(skip, skip + limit), total: nTx + nWtx, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
