export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'
import { requireActiveRider, activeDenied } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { limitHit } from '@/lib/rate-limit'
import { ticketView, TICKET_LIMITS } from '@/lib/support-ticket-view'

export async function OPTIONS() { return corsOptions() }

// GET → { ticket } one of the rider's own tickets, with its messages.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ticket not found' }, 404)
    await connectDB()
    const t: any = await SupportTicket.findOne({ _id: params.id, userId: a.id, role: 'user' }).lean()
    if (!t) return withCors({ error: 'Ticket not found' }, 404)
    return withCors({ ticket: ticketView(t) })
  } catch {
    return withCors({ error: 'Server error' }, 500)
  }
}

// POST { message } → the rider replies; a resolved/closed ticket re-opens
// (in_progress) so the admin sees it again.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ticket not found' }, 404)
    const b = await req.json().catch(() => ({}))
    const message = String(b.message || '').trim().slice(0, TICKET_LIMITS.MESSAGE)
    if (!message) return withCors({ error: 'Message required' }, 400)
    if (!(await limitHit(`ticket-reply:user:${a.id}`, 20, 10 * 60_000))) {
      return withCors({ error: 'Too many messages. Please wait a moment.', code: 'RATE_LIMITED' }, 429)
    }
    await connectDB()
    const t: any = await SupportTicket.findOneAndUpdate(
      { _id: params.id, userId: a.id, role: 'user' },
      { $push: { messages: { sender: 'user', message, sentAt: new Date() } } },
      { new: true },
    )
    if (!t) return withCors({ error: 'Ticket not found' }, 404)
    if (t.status === 'resolved' || t.status === 'closed') {
      t.status = 'in_progress'
      await t.save()
    }
    return withCors({ success: true, ticket: ticketView(t.toObject()) })
  } catch {
    return withCors({ error: 'Server error' }, 500)
  }
}
