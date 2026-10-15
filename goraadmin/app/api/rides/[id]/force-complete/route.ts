export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Admin escape hatch for a ride that has been priced but never settled — e.g.
// a cash rental where the driver's app died between collecting the money and
// calling /complete. Without this the ride sits at status 'ongoing' with
// rentalPhase 'completed' forever and the commission is never taken.
//
// This deliberately does NOT reimplement settlement: it clears awaitingPayment
// and forwards to /rides/{id}/complete so there is exactly one place where
// money moves.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const admin = requireAuth(req) as any
    if (!admin?.id) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (ride.status === 'completed') return withCors({ error: 'Already completed' }, 400)
    if (ride.status === 'cancelled') return withCors({ error: 'Ride was cancelled' }, 400)

    ride.awaitingPayment = false
    await ride.save()

    // Reuse the single settlement path (commission split, wallet, Transaction).
    const url = new URL(`/api/rides/${params.id}/complete`, req.nextUrl.origin)
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Forward the admin's credentials so /complete's ownership check can be
        // satisfied by the admin-override branch below.
        authorization: req.headers.get('authorization') || '',
        cookie: req.headers.get('cookie') || '',
        'x-admin-override': '1',
      },
      body: '{}',
    })
    const data = await res.json()
    return withCors({ forced: true, ...data }, res.status)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
