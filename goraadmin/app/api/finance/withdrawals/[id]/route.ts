import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'
import Driver from '@/models/Driver'
import Transaction from '@/models/Transaction'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'

// Must match app/api/auth/driver/withdraw (the mutex held while a request is pending).
const WITHDRAW_PENDING_TOKEN = 'wd:pending'

// PUT /api/finance/withdrawals/[id]  body: { action: 'approve'|'reject', note?, payoutRef? }
//
// The status is claimed atomically ({status:'pending'} → new status) before any
// money moves, so a double click / two admins can never process it twice.
//   approve → mark paid (status 'approved'). Requests made since holds exist
//             already took the money off the wallet at request time; a legacy
//             request (no hold) is debited now, only if the balance covers it.
//   reject  → reason required; a held amount goes back to the wallet once.
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    const admin: any = requireAdmin(req)
    const adminEmail = String(admin?.email || admin?.id || 'unknown')
    await connectDB()
    const body = await req.json().catch(() => ({}))
    const { action } = body
    const note = typeof body.note === 'string' ? body.note.trim().slice(0, 500) : ''
    const payoutRef = String(body.payoutRef || body.utr || '').trim().slice(0, 100)
    if (!['approve', 'reject'].includes(action)) {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
    if (action === 'reject' && !note) return NextResponse.json({ error: 'Rejection reason is required' }, { status: 400 })

    const now = new Date()
    const set: any = { status: action === 'approve' ? 'approved' : 'rejected', processedAt: now, processedBy: adminEmail }
    if (note) set.note = note
    if (action === 'approve' && payoutRef) set.payoutRef = payoutRef

    const w: any = await Withdrawal.findOneAndUpdate({ _id: params.id, status: 'pending' }, { $set: set }, { new: true }).lean()
    if (!w) {
      const exists = await Withdrawal.exists({ _id: params.id })
      if (!exists) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
      return NextResponse.json({ error: 'Already processed' }, { status: 400 })
    }
    const acct = `${w.bankName || 'bank'} ****${String(w.accountNumber || '').slice(-4)}`

    if (action === 'reject') {
      if (w.holdPlaced) {
        // Release once: flip holdReleased first, then credit.
        const rel = await Withdrawal.updateOne({ _id: w._id, holdReleased: { $ne: true } }, { $set: { holdReleased: true } })
        if (rel.modifiedCount === 1) {
          const d: any = await Driver.findOneAndUpdate(
            { _id: w.driverId },
            { $inc: { walletBalance: w.amount }, $pull: { walletRechargeRefs: WITHDRAW_PENDING_TOKEN } },
            { new: true },
          ).select('walletBalance').lean()
          await Transaction.create({
            driverId: w.driverId, type: 'withdrawal_released', amount: w.amount,
            description: `Withdrawal to ${acct} rejected — amount returned (${note})`,
            balanceAfter: d?.walletBalance,
          })
        }
      }
      return NextResponse.json({ ...w, holdReleased: w.holdPlaced ? true : w.holdReleased })
    }

    // approve
    if (w.holdPlaced) {
      await Driver.updateOne({ _id: w.driverId }, { $pull: { walletRechargeRefs: WITHDRAW_PENDING_TOKEN } })
      return NextResponse.json(w)
    }

    // Legacy request (made before holds): debit now, atomically.
    const d: any = await Driver.findOneAndUpdate(
      { _id: w.driverId, walletBalance: { $gte: w.amount } },
      { $inc: { walletBalance: -w.amount } },
      { new: true },
    ).select('walletBalance').lean()
    if (!d) {
      // Put it back to pending so it can be rejected or retried later.
      await Withdrawal.updateOne({ _id: w._id, status: 'approved' }, { $set: { status: 'pending' }, $unset: { processedAt: 1, processedBy: 1, payoutRef: 1 } })
      const exists = await Driver.exists({ _id: w.driverId })
      if (!exists) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
      return NextResponse.json({ error: 'Driver has insufficient wallet balance' }, { status: 402 })
    }
    await Transaction.create({
      driverId: w.driverId, type: 'withdrawal', amount: -w.amount,
      description: `Withdrawal to ${acct}`,
      balanceAfter: d.walletBalance,
    })
    return NextResponse.json(w)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
