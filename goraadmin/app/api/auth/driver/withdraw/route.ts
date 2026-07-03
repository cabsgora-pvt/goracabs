export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Withdrawal from '@/models/Withdrawal'
import Settings from '@/models/Settings'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/withdraw → driver's withdrawal history
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const withdrawals = await Withdrawal.find({ driverId: payload.id }).sort({ createdAt: -1 }).limit(50).lean()
    return withCors({ withdrawals })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST /api/auth/driver/withdraw
// body: { amount, accountHolderName, bankName, accountNumber, ifscCode }
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { amount, accountHolderName, bankName, accountNumber, ifscCode } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (!bankName || !accountNumber || !ifscCode) return withCors({ error: 'Select a bank account' }, 400)

    await connectDB()
    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const minWithdrawal = Math.round(Number(s?.driverApp?.minWithdrawal) || 100)
    if (amt < minWithdrawal) return withCors({ error: `Minimum withdrawal is ₹${minWithdrawal}` }, 400)

    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if ((driver.walletBalance || 0) < amt) {
      return withCors({ error: 'Insufficient wallet balance', balance: driver.walletBalance || 0 }, 402)
    }

    const w = await Withdrawal.create({
      driverId: driver._id,
      driverName: driver.name,
      driverPhone: driver.phone,
      vehicleType: driver.selectedVehicleTypeName || driver.vehicleType || '',
      zoneName: driver.zoneName || '',
      amount: amt,
      accountHolderName: accountHolderName || driver.name,
      bankName, accountNumber, ifscCode,
      status: 'pending',
    })

    return withCors({ success: true, withdrawal: w })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
