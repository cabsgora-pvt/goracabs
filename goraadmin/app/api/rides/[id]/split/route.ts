export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Last 10 digits — matches regardless of +91 / spaces / dashes in how the
// rider typed a friend's number.
function normPhone(p: string): string {
  const digits = String(p || '').replace(/\D/g, '')
  return digits.slice(-10)
}

// GET /api/rides/{id}/split → current split state (share amounts, who's paid)
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('fare splitRequests splitCollected').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ fare: ride.fare || 0, splitRequests: ride.splitRequests || [], splitCollected: ride.splitCollected || 0 })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

// POST /api/rides/{id}/split  body: { contacts: [{ phone, name }] }
// Only the ride's own rider can set this up, and only before anyone has paid
// — once a friend has paid their share, changing the split would leave their
// payment attached to a number that no longer matches.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireAuth(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { contacts } = await req.json()
    if (!Array.isArray(contacts) || contacts.length === 0 || contacts.length > 3) {
      return withCors({ error: 'Add 1 to 3 people to split with' }, 400)
    }

    await connectDB()
    const ride: any = await Ride.findById(params.id)
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (String(ride.riderId) !== String(payload.id)) return withCors({ error: 'Unauthorized' }, 401)
    if (ride.status === 'completed' || ride.status === 'cancelled') {
      return withCors({ error: 'This ride is already over' }, 400)
    }
    if ((ride.splitRequests || []).some((s: any) => s.status === 'paid')) {
      return withCors({ error: 'Someone already paid their share — the split can’t be changed now' }, 400)
    }

    const fare = ride.fare || 0
    const people = 1 + contacts.length
    const share = Math.floor((fare / people) * 100) / 100 // each co-rider's share; the rider covers the rounding remainder

    ride.splitRequests = contacts.map((c: any) => ({
      phone: normPhone(c.phone), name: String(c.name || '').trim() || 'Friend',
      share, status: 'pending',
    }))
    await ride.save()

    return withCors({ success: true, fare, share, splitRequests: ride.splitRequests })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
