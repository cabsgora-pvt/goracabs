export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Transaction from '@/models/Transaction'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/wallet → { balance, transactions } for the authed driver
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).select('walletBalance').lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    const transactions = await Transaction.find({ driverId: payload.id })
      .sort({ createdAt: -1 }).limit(100).lean()

    return withCors({ balance: driver.walletBalance || 0, transactions })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
