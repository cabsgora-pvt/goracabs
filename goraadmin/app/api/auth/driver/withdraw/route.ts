export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Withdrawal from '@/models/Withdrawal'
import Settings from '@/models/Settings'
import Transaction from '@/models/Transaction'
import { requireDriverAuth, requireActiveDriver } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { holdOf, holdMessage } from '@/lib/account-hold'

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
const RECENT_BANK_MS = 7 * 24 * 60 * 60 * 1000

type SavedAccount = { id: string; accountHolderName?: string; bankName?: string; accountNumber?: string; ifscCode?: string; changedAt?: Date | null }

// The driver's saved payout accounts (GET /auth/driver/banks lists the same):
// bankAccounts, else the registration bankDetails. When each was added or last
// changed: a bankAccounts entry's own ObjectId time; bankDetails' bankUpdatedAt.
function savedAccounts(driver: any): SavedAccount[] {
  const list: SavedAccount[] = (driver.bankAccounts || [])
    .filter((a: any) => a?.accountNumber)
    .map((a: any) => ({
      id: String(a._id || ''), accountHolderName: a.accountHolderName, bankName: a.bankName,
      accountNumber: a.accountNumber, ifscCode: a.ifscCode,
      changedAt: a._id && mongoose.isValidObjectId(String(a._id)) ? new mongoose.Types.ObjectId(String(a._id)).getTimestamp() : null,
    }))
  if (!list.length && driver.bankDetails?.accountNumber) {
    list.push({
      id: 'bankDetails', accountHolderName: driver.bankDetails.accountHolderName || driver.name,
      bankName: driver.bankDetails.bankName, accountNumber: driver.bankDetails.accountNumber,
      ifscCode: driver.bankDetails.ifscCode, changedAt: driver.bankUpdatedAt ? new Date(driver.bankUpdatedAt) : null,
    })
  }
  return list
}

const norm = (v: unknown) => String(v || '').replace(/\s+/g, '').toUpperCase()

// POST /api/auth/driver/withdraw
// body: { amount, accountId? }  (installed apps also send the selected
//        account's accountNumber/ifscCode: used ONLY to pick which saved account
//        it is — the payout details always come from the driver's saved record)
// The amount is HELD (taken off the wallet) when the request is made, so the
// driver cannot spend it again while the admin reviews it. Reject gives it
// back; approve only marks it paid. One pending request at a time.
// Refused (403) unless the driver is approved and not on hold / blocked.
// A request to an account added or changed in the last 7 days is flagged
// bankChangedRecently for the admin.
export async function POST(req: NextRequest) {
  try {
    const auth = await requireActiveDriver(req)
    if (!auth.ok) return withCors({ error: auth.error, code: auth.code }, auth.status)

    const body = await req.json().catch(() => ({}))
    const amt = Number(body?.amount)
    if (!Number.isFinite(amt) || amt <= 0) return withCors({ error: 'Enter a valid amount' }, 400)

    await connectDB()
    const driver: any = await Driver.findById(auth.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if (driver.status !== 'approved') {
      return withCors({ error: 'Withdrawals are available once your account is approved.', code: 'notApproved' }, 403)
    }
    const hold = holdOf(driver)
    if (hold.held) return withCors({ error: holdMessage(hold), code: 'accountHold', accountHold: true, holdKind: hold.kind }, 403)

    // The payout account: picked from what the driver saved, never taken from
    // the request body.
    const accounts = savedAccounts(driver)
    let acct: SavedAccount | undefined
    const accountId = body?.accountId ? String(body.accountId) : ''
    if (accountId) acct = accounts.find(a => a.id === accountId)
    else if (body?.accountNumber) {
      acct = accounts.find(a => norm(a.accountNumber) === norm(body.accountNumber) && (!body.ifscCode || norm(a.ifscCode) === norm(body.ifscCode)))
    } else if (accounts.length === 1) acct = accounts[0]
    if (!acct) {
      return withCors({
        error: accounts.length ? 'Select one of your saved bank accounts' : 'Add a bank account first',
        code: accounts.length ? 'bankAccountNotFound' : 'bankAccountRequired',
      }, 400)
    }
    const bankChangedRecently = !!acct.changedAt && Date.now() - acct.changedAt.getTime() < RECENT_BANK_MS

    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const minWithdrawal = Math.round(Number(s?.driverApp?.minWithdrawal) || 100)
    const value = Math.round(amt)
    if (value !== amt) return withCors({ error: 'Enter a whole amount' }, 400)
    if (value < minWithdrawal) return withCors({ error: `Minimum withdrawal is ₹${minWithdrawal}` }, 400)
    if (value > 1000000) return withCors({ error: 'Amount too large' }, 400)

    if (await Withdrawal.exists({ driverId: driver._id, status: 'pending' })) {
      return withCors({ error: 'You already have a withdrawal request pending. Please wait for it to be processed.' }, 409)
    }

    // Hold: balance check + deduction + mutex in one atomic update — and still
    // approved / not held at that instant.
    const held: any = await Driver.findOneAndUpdate(
      {
        _id: driver._id, status: 'approved', 'accountHold.active': { $ne: true },
        walletBalance: { $gte: value }, walletRechargeRefs: { $ne: WITHDRAW_PENDING_TOKEN },
      },
      { $inc: { walletBalance: -value }, $push: { walletRechargeRefs: WITHDRAW_PENDING_TOKEN } },
      { new: true },
    ).select('walletBalance').lean()
    if (!held) {
      const d: any = await Driver.findById(driver._id).select('walletBalance walletRechargeRefs status accountHold').lean()
      if ((d?.walletRechargeRefs || []).includes(WITHDRAW_PENDING_TOKEN)) {
        return withCors({ error: 'You already have a withdrawal request pending. Please wait for it to be processed.' }, 409)
      }
      if (d?.status !== 'approved' || d?.accountHold?.active) return withCors({ error: 'Withdrawals are not available on this account right now.', code: 'accountHold' }, 403)
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
        accountHolderName: acct.accountHolderName || driver.name,
        bankName: acct.bankName || '', accountNumber: acct.accountNumber || '', ifscCode: acct.ifscCode || '',
        accountId: acct.id,
        bankChangedRecently,
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
      description: `Withdrawal requested to ${acct.bankName || 'bank'} ****${String(acct.accountNumber || '').slice(-4)} (on hold until processed)`,
      balanceAfter: held.walletBalance,
    })

    return withCors({ success: true, withdrawal: w, walletBalance: held.walletBalance })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
