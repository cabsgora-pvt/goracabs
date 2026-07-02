export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { createRazorpayOrder } from '@/lib/razorpay'

export async function OPTIONS() { return corsOptions() }

// POST /api/payment/razorpay/order  body: { amount, purpose, rideId? }
// Creates a Razorpay order and returns { orderId, keyId, amount, currency }.
export async function POST(req: NextRequest) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { amount, purpose = 'wallet', rideId = '' } = await req.json()
    const amt = Math.round(Number(amount) || 0)
    if (amt <= 0) return withCors({ error: 'Invalid amount' }, 400)

    const receipt = `${purpose}_${payload.id}_${Date.now()}`.slice(0, 40)
    const result = await createRazorpayOrder(amt, receipt, {
      userId: String(payload.id),
      purpose: String(purpose),
      rideId: String(rideId),
    })
    if (!result.ok) return withCors({ error: result.error }, 502)

    return withCors({
      orderId: result.order.id,
      keyId: result.keyId,
      amount: result.order.amount,
      currency: result.order.currency,
    })
  } catch {
    return withCors({ error: 'Failed to create order' }, 500)
  }
}
