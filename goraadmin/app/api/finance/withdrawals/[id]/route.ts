import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Withdrawal from '@/models/Withdrawal'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { action, note } = await req.json()
    if (!['approve', 'reject'].includes(action)) {
      return NextResponse.json({ error: 'Invalid action' }, { status: 400 })
    }
    const status = action === 'approve' ? 'approved' : 'rejected'
    const withdrawal = await Withdrawal.findByIdAndUpdate(
      params.id,
      { status, note, processedAt: new Date() },
      { new: true }
    ).lean()
    if (!withdrawal) return NextResponse.json({ error: 'Withdrawal not found' }, { status: 404 })
    return NextResponse.json(withdrawal)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
