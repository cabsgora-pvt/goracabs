export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Transaction from '@/models/Transaction'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'

// POST /api/drivers/[id]/wallet  body: { amount, type: 'credit'|'debit', note }
// Admin manually adds or deducts money from a driver's wallet. One atomic $inc;
// recorded as admin_credit / admin_debit (never 'recharge' / 'withdrawal', so
// reports don't mix manual adjustments with real top-ups and payouts), with
// the admin's email in the description. A debit may take the wallet below zero
// (admins use it to book dues), as before.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    const admin: any = requireAdmin(req)
    const adminEmail = String(admin?.email || admin?.id || 'unknown')
    await connectDB()
    const { amount, type = 'credit', note = '' } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (amt <= 0 || amt > 100000) return NextResponse.json({ error: 'Invalid amount' }, { status: 400 })
    if (!['credit', 'debit'].includes(type)) return NextResponse.json({ error: 'Invalid type' }, { status: 400 })
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    const reason = typeof note === 'string' ? note.trim().slice(0, 300) : ''

    const delta = type === 'debit' ? -amt : amt
    const driver: any = await Driver.findOneAndUpdate({ _id: params.id }, { $inc: { walletBalance: delta } }, { new: true })
      .select('walletBalance').lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })

    await Transaction.create({
      driverId: driver._id, type: type === 'debit' ? 'admin_debit' : 'admin_credit', amount: delta,
      description: `${reason || (type === 'debit' ? 'Admin deduction' : 'Admin credit')} (by ${adminEmail})`,
      balanceAfter: driver.walletBalance,
    })

    return NextResponse.json({ success: true, walletBalance: driver.walletBalance })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed' }, { status: 500 })
  }
}
