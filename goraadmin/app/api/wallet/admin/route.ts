import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

// GET /api/wallet/admin?userId=  → { balance, transactions } (admin user-detail page)
export async function GET(req: NextRequest) {
  try {
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
// Admin manually increases/decreases a user's balance with a note.
export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const { userId, amount, type, note } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (!userId || amt <= 0 || !['credit', 'debit'].includes(type)) {
      return Response.json({ error: 'userId, positive amount and valid type required' }, { status: 400 })
    }
    const user = await User.findById(userId)
    if (!user) return Response.json({ error: 'User not found' }, { status: 404 })
    const cur = user.walletBalance || 0
    if (type === 'debit' && amt > cur) return Response.json({ error: 'Amount exceeds balance' }, { status: 400 })
    user.walletBalance = type === 'credit' ? cur + amt : cur - amt
    await user.save()
    await WalletTransaction.create({
      userId: user._id, type, amount: amt, balanceAfter: user.walletBalance,
      note: note || (type === 'credit' ? 'Added by admin' : 'Deducted by admin'), source: 'admin',
    })
    return Response.json({ balance: user.walletBalance })
  } catch (e: any) {
    return Response.json({ error: e.message }, { status: 400 })
  }
}
