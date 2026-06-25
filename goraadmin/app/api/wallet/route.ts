import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

export async function OPTIONS() { return corsOptions() }

// GET /api/wallet → { balance, transactions } for the authed user
export async function GET(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const user = await User.findById(payload.id).select('walletBalance').lean() as any
    if (!user) return withCors({ error: 'User not found' }, 404)
    const transactions = await WalletTransaction.find({ userId: payload.id }).sort({ createdAt: -1 }).limit(100).lean()
    return withCors({ balance: user.walletBalance || 0, transactions })
  } catch {
    return withCors({ error: 'Failed' }, 500)
  }
}

// POST /api/wallet  body: { amount }  → add money (no gateway; simulated recharge)
export async function POST(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { amount } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (amt <= 0) return withCors({ error: 'Invalid amount' }, 400)
    await connectDB()
    const user = await User.findById(payload.id)
    if (!user) return withCors({ error: 'User not found' }, 404)
    user.walletBalance = (user.walletBalance || 0) + amt
    await user.save()
    await WalletTransaction.create({
      userId: user._id, type: 'credit', amount: amt, balanceAfter: user.walletBalance,
      note: 'Money added to wallet', source: 'recharge',
    })
    return withCors({ balance: user.walletBalance })
  } catch {
    return withCors({ error: 'Failed' }, 500)
  }
}
