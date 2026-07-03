import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'
import Driver from '@/models/Driver'
import Transaction from '@/models/Transaction'

// PUT /api/finance/withdrawals/[id]  body: { action: 'approve'|'reject', note }
// Approve → deduct the amount from the driver's wallet + log a transaction.
// Reject → mark rejected with a reason (note required).
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { action, note } = await req.json()
    if (!['approve', 'reject'].includes(action)) {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }

    const withdrawal: any = await Withdrawal.findById(params.id)
    if (!withdrawal) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
    if (withdrawal.status !== 'pending') {
      return NextResponse.json({ error: 'Already processed' }, { status: 400 })
    }

    if (action === 'reject') {
      if (!note || !note.trim()) return NextResponse.json({ error: 'Rejection reason is required' }, { status: 400 })
      withdrawal.status = 'rejected'
      withdrawal.note = note.trim()
      withdrawal.processedAt = new Date()
      await withdrawal.save()
      return NextResponse.json(withdrawal.toObject())
    }

    // approve → deduct from wallet
    const driver: any = await Driver.findById(withdrawal.driverId)
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    if ((driver.walletBalance || 0) < withdrawal.amount) {
      return NextResponse.json({ error: 'Driver has insufficient wallet balance' }, { status: 402 })
    }

    driver.walletBalance = (driver.walletBalance || 0) - withdrawal.amount
    await driver.save()
    await Transaction.create({
      driverId: driver._id, type: 'withdrawal', amount: -withdrawal.amount,
      description: `Withdrawal to ${withdrawal.bankName} ****${(withdrawal.accountNumber || '').slice(-4)}`,
      balanceAfter: driver.walletBalance,
    })

    withdrawal.status = 'approved'
    if (note) withdrawal.note = note
    withdrawal.processedAt = new Date()
    await withdrawal.save()

    return NextResponse.json(withdrawal.toObject())
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
