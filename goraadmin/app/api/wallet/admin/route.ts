import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

// GET /api/wallet/admin?userId=  → { balance, transactions } (admin user-detail page)
export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const userId = req.nextUrl.searchParams.get('userId')
    if (!userId) return Response.json({ error: 'userId required' }, { status: 400 })
    const user = await User.findById(userId).select('walletBalance name phone').lean() as any
    if (!user) return Response.json({ error: 'User not found' }, { status: 404 })
    const transactions = await WalletTransaction.find({ userId }).sort({ createdAt: -1 }).limit(100).lean()
    return Response.json({ balance: user.walletBalance || 0, transactions })
  } catch (e: any) {
    return Response.json({ error: e.message }, { status: 500 })
  }
}

// POST /api/wallet/admin  body: { userId, amount, type: 'credit'|'debit', note }
// Admin manually increases/decreases a user's balance. A reason (note) is
// required; the row records which admin did it (ref `admin:<email>`). The
// change is one atomic $inc — a debit only applies while the balance covers it.
export async function POST(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    const admin: any = requireAdmin(req)
    const adminEmail = String(admin?.email || admin?.id || 'unknown')
    await connectDB()
    const { userId, amount, type, note } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    const reason = typeof note === 'string' ? note.trim().slice(0, 300) : ''
    if (!userId || !mongoose.isValidObjectId(userId) || amt <= 0 || amt > 100000 || !['credit', 'debit'].includes(type)) {
      return Response.json({ error: 'userId, amount (1-100000) and valid type required' }, { status: 400 })
    }
    if (!reason) return Response.json({ error: 'A reason is required' }, { status: 400 })

    const filter: any = { _id: userId }
    if (type === 'debit') filter.walletBalance = { $gte: amt }
    const user: any = await User.findOneAndUpdate(filter, { $inc: { walletBalance: type === 'credit' ? amt : -amt } }, { new: true })
      .select('walletBalance').lean()
    if (!user) {
      const exists = await User.exists({ _id: userId })
      if (!exists) return Response.json({ error: 'User not found' }, { status: 404 })
      return Response.json({ error: 'Amount exceeds balance' }, { status: 400 })
    }
    await WalletTransaction.create({
      userId: user._id, type, amount: amt, balanceAfter: user.walletBalance,
      note: `${type === 'credit' ? 'Added by admin' : 'Deducted by admin'}: ${reason}`, source: 'admin',
      ref: `admin:${adminEmail}`,
    })
    return Response.json({ balance: user.walletBalance })
  } catch (e: any) {
    return Response.json({ error: e.message }, { status: 400 })
  }
}
