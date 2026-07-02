export const dynamic = 'force-dynamic'
import { withCors, corsOptions } from '@/lib/cors'
import { getRazorpayConfig } from '@/lib/razorpay'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'

export async function OPTIONS() { return corsOptions() }

// GET /api/payment/config → public-safe payment config for the app.
// Returns which methods are enabled + the Razorpay public keyId (NO secret).
export async function GET() {
  try {
    const cfg = await getRazorpayConfig()
    await connectDB()
    const s: any = await Settings.findOne({ key: 'global' }).lean()
    const pay = s?.payment || {}
    return withCors({
      razorpay: { enabled: cfg.enabled, keyId: cfg.enabled ? cfg.keyId : '', mode: cfg.mode },
      cashEnabled: pay.cashEnabled !== false,
      walletEnabled: pay.walletEnabled !== false,
    })
  } catch {
    return withCors({ razorpay: { enabled: false, keyId: '', mode: 'test' }, cashEnabled: true, walletEnabled: true })
  }
}
