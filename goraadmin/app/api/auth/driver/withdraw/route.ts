export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Withdrawal from '@/models/Withdrawal'
import Settings from '@/models/Settings'
import Transaction from '@/models/Transaction'
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

// Mutex token on the driver: present while a held withdrawal is pending, so
// two parallel requests cannot both open one (the check is in the same atomic
// update that takes the money).
const WITHDRAW_PENDING_TOKEN = 'wd:pending'

// POST /api/auth/driver/withdraw
// body: { amount, accountHolderName, bankName, accountNumber, ifscCode }
// The amount is HELD (taken off the wallet) when the request is made, so the
// driver cannot spend it again while the admin reviews it. Reject gives it
// back; approve only marks it paid. One pending request at a time.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { amount, accountHolderName, bankName, accountNumber, ifscCode } = await req.json()
    const amt = Number(amount)
    if (!bankName || !accountNumber || !ifscCode) return withCors({ error: 'Select a bank account' }, 400)
    if (!Number.isFinite(amt) || amt <= 0) return withCors({ error: 'Enter a valid amount' }, 400)

    await connectDB()
    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const minWithdrawal = Math.round(Number(s?.driverApp?.minWithdrawal) || 100)
    const value = Math.round(amt)
    if (value !== amt) return withCors({ error: 'Enter a whole amount' }, 400)
    if (value < minWithdrawal) return withCors({ error: `Minimum withdrawal is ₹${minWithdrawal}` }, 400)
    if (value > 1000000) return withCors({ error: 'Amount too large' }, 400)

    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if (await Withdrawal.exists({ driverId: driver._id, status: 'pending' })) {
      return withCors({ error: 'You already have a withdrawal request pending. Please wait for it to be processed.' }, 409)
    }

    // Hold: balance check + deduction + mutex in one atomic update.
    const held: any = await Driver.findOneAndUpdate(
      { _id: driver._id, walletBalance: { $gte: value }, walletRechargeRefs: { $ne: WITHDRAW_PENDING_TOKEN } },
      { $inc: { walletBalance: -value }, $push: { walletRechargeRefs: WITHDRAW_PENDING_TOKEN } },
      { new: true },
    ).select('walletBalance').lean()
    if (!held) {
      const d: any = await Driver.findById(driver._id).select('walletBalance walletRechargeRefs').lean()
      if ((d?.walletRechargeRefs || []).includes(WITHDRAW_PENDING_TOKEN)) {
        return withCors({ error: 'You already have a withdrawal request pending. Please wait for it to be processed.' }, 409)
      }
      return withCors({ error: 'Insufficient wallet balance', balance: d?.walletBalance || 0 }, 402)
    }

    let w: any
    try {
      w = await Withdrawal.create({
        driverId: driver._id,
        driverName: driver.name,
        driverPhone: driver.phone,
        vehicleType: driver.selectedVehicleTypeName || driver.vehicleType || '',
        zoneName: driver.zoneName || '',
        amount: value,
        accountHolderName: accountHolderName || driver.name,
        bankName, accountNumber, ifscCode,
        status: 'pending',
        holdPlaced: true,
      })
    } catch (e) {
      // Could not record the request: give the hold straight back.
      await Driver.updateOne({ _id: driver._id }, { $inc: { walletBalance: value }, $pull: { walletRechargeRefs: WITHDRAW_PENDING_TOKEN } })
      throw e
    }
    await Transaction.create({
      driverId: driver._id, type: 'withdrawal_hold', amount: -value,
      description: `Withdrawal requested to ${bankName} ****${String(accountNumber).slice(-4)} (on hold until processed)`,
      balanceAfter: held.walletBalance,
    })

    return withCors({ success: true, withdrawal: w, walletBalance: held.walletBalance })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
