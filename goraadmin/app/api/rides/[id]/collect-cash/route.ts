export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { collectCash } from '@/lib/settlement'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/collect-cash — assigned driver only.
// A completed ONLINE ride the rider has not paid: the driver takes cash
// instead. The ride becomes paymentMode 'cash' / paymentStatus 'paid' and the
// commission is debited from the driver's wallet exactly like a cash ride
// (atomic, once). Not for outstation trips paid at booking.
// → { success, paymentMode:'cash', paymentStatus:'paid', cashToCollect, commission, driverWalletBalance }
//   409 { code:'paidOnline' } when a verified online payment is being applied.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const driver = requireDriverAuth(req) as any
    if (!driver?.id) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    await connectDB()
    const out = await collectCash(params.id, String(driver.id))
    return withCors(out.body, out.status)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
