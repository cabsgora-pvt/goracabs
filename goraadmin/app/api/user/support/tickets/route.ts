export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import Ride from '@/models/Ride'
import SupportTicket from '@/models/SupportTicket'
import { requireActiveRider, activeDenied } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { limitHit } from '@/lib/rate-limit'
import { ticketView, TICKET_LIMITS, TICKET_CATEGORIES } from '@/lib/support-ticket-view'

export async function OPTIONS() { return corsOptions() }

// Rider support tickets (the rider app's Support screen). The app used to
// show three hard-coded tickets and its "Submit Ticket" created nothing —
// it only showed a success message, so riders' complaints never reached the
// admin. Mirrors the driver's /auth/driver/support/tickets.
// GET → { tickets: [...] } the rider's own, newest activity first.
export async function GET(req: NextRequest) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    await connectDB()
    const rows: any[] = await SupportTicket.find({ userId: a.id, role: 'user' }).sort({ updatedAt: -1 }).limit(50).lean()
    return withCors({ tickets: rows.map(ticketView) })
  } catch {
    return withCors({ error: 'Server error' }, 500)
  }
}

// POST { subject, message, category?, rideId? } → 201 { success, ticket }.
// rideId, when sent, must be one of this rider's rides.
export async function POST(req: NextRequest) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    const b = await req.json().catch(() => ({}))
    const subject = String(b.subject || '').trim().slice(0, TICKET_LIMITS.SUBJECT)
    const message = String(b.message || '').trim().slice(0, TICKET_LIMITS.MESSAGE)
    if (!subject || !message) return withCors({ error: 'Subject and message are required', code: 'TICKET_FIELDS' }, 400)
    const category = TICKET_CATEGORIES.has(String(b.category || '').toLowerCase()) ? String(b.category).toLowerCase() : 'general'
    if (!(await limitHit(`ticket:user:${a.id}`, TICKET_LIMITS.PER_10_MIN, 10 * 60_000))) {
      return withCors({ error: 'Too many tickets. Please wait a few minutes.', code: 'RATE_LIMITED' }, 429)
    }
    await connectDB()
    let rideId: any = undefined
    if (b.rideId) {
      if (!mongoose.isValidObjectId(String(b.rideId))) return withCors({ error: 'Invalid ride', code: 'BAD_RIDE' }, 400)
      const own = await Ride.exists({ _id: b.rideId, riderId: a.id })
      if (!own) return withCors({ error: 'Ride not found', code: 'BAD_RIDE' }, 404)
      rideId = b.rideId
    }
    const u: any = await User.findById(a.id).select('name phone').lean()
    const ticket = await SupportTicket.create({
      userId: a.id,
      role: 'user',
      userName: u?.name || 'Rider',
      subject,
      category,
      ...(rideId ? { rideId } : {}),
      status: 'open',
      priority: category === 'safety' ? 'high' : 'medium',
      messages: [{ sender: 'user', message, sentAt: new Date() }],
    })
    return withCors({ success: true, ticket: ticketView(ticket.toObject()) }, 201)
  } catch {
    return withCors({ error: 'Server error' }, 500)
  }
}
