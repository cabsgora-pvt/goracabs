export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/auth/driver/banks → { driverName, banks: [...] }
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    let banks = driver.bankAccounts || []
    // Migrate the registration bankDetails into the list if none saved yet
    if (banks.length === 0 && driver.bankDetails?.accountNumber) {
      banks = [{
        accountHolderName: driver.bankDetails.accountHolderName || driver.name,
        bankName: driver.bankDetails.bankName,
        accountNumber: driver.bankDetails.accountNumber,
        ifscCode: driver.bankDetails.ifscCode,
      }]
    }
    return withCors({ driverName: driver.name || '', banks })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST /api/auth/driver/banks  body: { accountHolderName, bankName, accountNumber, ifscCode }
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { accountHolderName, bankName, accountNumber, ifscCode } = await req.json()
    if (!accountHolderName || !bankName || !accountNumber || !ifscCode) {
      return withCors({ error: 'All bank fields are required' }, 400)
    }
    await connectDB()
    const driver: any = await Driver.findById(payload.id)
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if (!Array.isArray(driver.bankAccounts)) driver.bankAccounts = []
    driver.bankAccounts.push({ accountHolderName, bankName, accountNumber, ifscCode })
    await driver.save()
    return withCors({ success: true, banks: driver.bankAccounts })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
