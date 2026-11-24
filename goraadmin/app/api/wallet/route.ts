import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import User from '@/models/User'
import WalletTransaction from '@/models/WalletTransaction'

export async function OPTIONS() { return corsOptions() }

// GET /api/wallet → { balance, transactions } for the authed rider
export async function GET(req: NextRequest) {
  try {
    const payload = requireRider(req) as any
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

// POST /api/wallet used to add ANY amount the app sent to the rider's wallet
// ("simulated recharge", no gateway) — i.e. it minted money. Gone: the only
// way to add money is a Razorpay payment verified by the server
// (/api/payment/razorpay/order + /verify, purpose 'wallet').
export async function POST() {
  return withCors({
    error: 'Adding money without a payment is no longer supported. Please add money with online payment (Razorpay).',
    gone: true,
  }, 410)
}
