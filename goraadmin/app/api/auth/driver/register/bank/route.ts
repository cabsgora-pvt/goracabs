export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { registrationLocked } from '@/lib/driver-registration'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { accountHolderName, bankName, branch, accountNumber, ifscCode, accountType } = await req.json()
    if (!accountHolderName || !bankName || !accountNumber || !ifscCode) {
      return withCors({ error: 'Account holder name, bank name, account number and IFSC are required' }, 400)
    }

    await connectDB()
    const current: any = await Driver.findById(payload.id).select('status registrationStep').lean()
    if (!current) return withCors({ error: 'Driver not found' }, 404)
    const bankDetails = { accountHolderName, bankName, branch, accountNumber, ifscCode, accountType: accountType === 'current' ? 'current' : 'savings' }
    // Under review / approved: save the bank details only — never move the
    // driver's status (a blocked driver used to come back as 'pending' here).
    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      registrationLocked(current)
        ? { bankDetails, bankUpdatedAt: new Date() }
        : { bankDetails, bankUpdatedAt: new Date(), registrationStep: 'submitted', status: 'pending' },
      { new: true }
    ).select('_id').lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
