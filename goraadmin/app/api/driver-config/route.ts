export const dynamic = 'force-dynamic'
import { withCors, corsOptions } from '@/lib/cors'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'

export async function OPTIONS() { return corsOptions() }

// GET /api/driver-config → public driver-app config (per-service ringtones + wallet rules)
export async function GET() {
  try {
    await connectDB()
    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const da = s?.driverApp || {}
    return withCors({
      ringtones: da.ringtones || {},
      walletBlockEnabled: da.walletBlockEnabled !== false,
      maxNegativeWallet: da.maxNegativeWallet ?? 500,
    })
  } catch {
    return withCors({ ringtones: {} })
  }
}
