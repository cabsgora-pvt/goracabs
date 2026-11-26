export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdmin } from '@/lib/admin-audit'

// POST { id } — the full bank details of one withdrawal, to make the transfer
// before approving it. Behind the admin password (5-min sudo) and audited:
// the list only shows the last 4 digits.
export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    const b = await req.json().catch(() => ({}))
    if (!mongoose.isValidObjectId(String(b.id || ''))) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
    await connectDB()
    const w: any = await Withdrawal.findById(b.id).select('driverName amount accountHolderName bankName accountNumber ifscCode status bankChangedRecently').lean()
    if (!w) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
    await auditAdmin(req, requireAdmin(req), 'withdrawal.bank.view', {
      target: `withdrawal:${w._id}`,
      summary: `Viewed payout bank details — ${w.driverName || 'driver'} ₹${w.amount} ****${String(w.accountNumber || '').slice(-4)}`,
    })
    return NextResponse.json({ bank: {
      accountHolderName: w.accountHolderName || '', bankName: w.bankName || '',
      accountNumber: w.accountNumber || '', ifscCode: w.ifscCode || '',
    } })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
