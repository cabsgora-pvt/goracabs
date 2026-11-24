export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireRider, requireDriverAuth, requireAdmin } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { completeRide, type Actor } from '@/lib/settlement'

export async function OPTIONS() { return corsOptions() }

// POST → end an ONGOING ride and settle it (lib/settlement.ts has the rules).
//   driver  (assigned)            → any payment mode
//   admin   (x-admin-override: 1) → any payment mode (force-complete)
//   rider                         → online rides only, and only as "the driver
//                                   ended it": the ride stays unpaid until a
//                                   verified Razorpay payment arrives.
// Response: { success, paymentStatus, paymentMode, amountDue, couponDiscount,
//   awaitingPayment, paymentSwitchedToCash?, cashToCollect?, fare,
//   commissionPercent, adminProfit, driverEarning, driverWalletBalance, codSettled }
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    const asDriver = requireDriverAuth(req) as any
    const asRider = requireRider(req) as any
    const asAdmin = req.headers.get('x-admin-override') === '1' ? requireAdmin(req) as any : null
    let actor: Actor | null = null
    if (asDriver?.id) actor = { kind: 'driver', id: String(asDriver.id) }
    else if (asAdmin?.id) actor = { kind: 'admin', id: String(asAdmin.id) }
    else if (asRider?.id) actor = { kind: 'rider', id: String(asRider.id) }
    if (!actor) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const out = await completeRide(params.id, actor)
    return withCors(out.body, out.status)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
