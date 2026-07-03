export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → one ticket (with messages) belonging to the driver
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const ticket: any = await SupportTicket.findOne({ _id: params.id, driverId: payload.id }).lean()
    if (!ticket) return withCors({ error: 'Ticket not found' }, 404)
    return withCors({ ticket })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST → driver adds a reply message  body: { message }
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { message } = await req.json()
    if (!message) return withCors({ error: 'Message required' }, 400)

    await connectDB()
    const ticket: any = await SupportTicket.findOne({ _id: params.id, driverId: payload.id })
    if (!ticket) return withCors({ error: 'Ticket not found' }, 404)
    ticket.messages.push({ sender: 'driver', message, sentAt: new Date() })
    if (ticket.status === 'resolved' || ticket.status === 'closed') ticket.status = 'in_progress'
    await ticket.save()
    return withCors({ success: true, ticket: ticket.toObject() })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
