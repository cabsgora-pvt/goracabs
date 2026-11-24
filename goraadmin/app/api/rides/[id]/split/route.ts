export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import mongoose from 'mongoose'
import User from '@/models/User'
import { requireRider, requireDriverAuth, requireAdmin } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Last 10 digits — matches regardless of +91 / spaces / dashes in how the
// rider typed a friend's number.
function normPhone(p: string): string {
  const digits = String(p || '').replace(/\D/g, '')
  return digits.slice(-10)
}

// GET /api/rides/{id}/split → current split state (share amounts, who's paid).
// Participants only: the ride's rider, its assigned driver, a co-rider named
// in the split, or an admin. It used to be public and listed every
// co-rider's phone number to anyone who knew a ride id. A co-rider sees the
// other co-riders' numbers masked.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    const rider = requireRider(req) as any
    const driver = requireDriverAuth(req) as any
    const admin = requireAdmin(req) as any
    if (!rider && !driver && !admin) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('fare riderId driverId splitRequests splitCollected').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    const reqs: any[] = ride.splitRequests || []
    const isOwner = !!rider && String(ride.riderId) === String(rider.id)
    const isDriver = !!driver && !!ride.driverId && String(ride.driverId) === String(driver.id)
    let myPhone = ''
    if (rider && !isOwner) {
      const u: any = await User.findById(rider.id).select('phone').lean()
      myPhone = normPhone(u?.phone || rider.phone || '')
    }
    const isCoRider = !!myPhone && reqs.some(s => s.phone === myPhone)
    if (!isOwner && !isDriver && !isCoRider && !admin) return withCors({ error: 'Not a participant in this ride' }, 403)
    const mask = (p: string) => (p && p.length >= 4 ? '******' + p.slice(-4) : '')
    const list = reqs.map(s => ({
      ...s,
      phone: isOwner || admin || s.phone === myPhone ? s.phone : mask(s.phone),
    }))
    return withCors({ fare: ride.fare || 0, splitRequests: list, splitCollected: ride.splitCollected || 0 })
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
    const payload = requireRider(req) as any
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
