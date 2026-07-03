export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Transaction from '@/models/Transaction'

// POST /api/drivers/[id]/wallet  body: { amount, type: 'credit'|'debit', note }
// Admin manually adds or deducts money from a driver's wallet.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { amount, type = 'credit', note = '' } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (amt <= 0) return NextResponse.json({ error: 'Invalid amount' }, { status: 400 })

    const driver: any = await Driver.findById(params.id)
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })

    if (type === 'debit') {
      driver.walletBalance = (driver.walletBalance || 0) - amt
      await driver.save()
      await Transaction.create({
        driverId: driver._id, type: 'withdrawal', amount: -amt,
        description: note || 'Admin deduction', balanceAfter: driver.walletBalance,
      })
    } else {
      driver.walletBalance = (driver.walletBalance || 0) + amt
      await driver.save()
      await Transaction.create({
        driverId: driver._id, type: 'recharge', amount: amt,
        description: note || 'Admin credit', balanceAfter: driver.walletBalance,
      })
    }

    return NextResponse.json({ success: true, walletBalance: driver.walletBalance })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed' }, { status: 500 })
  }
}
