import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'

const STATUSES = ['open', 'in_progress', 'resolved', 'closed']

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })
    await connectDB()
    const ticket = await SupportTicket.findById(params.id).lean()
    if (!ticket) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })
    return NextResponse.json(ticket)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

// PUT { message?, status? } — reply and status are separate actions: a reply
// never resolves or closes a ticket. A reply to an OPEN ticket moves it to
// in_progress (someone is on it); otherwise the status changes only when
// `status` is sent.
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })
    await connectDB()
    const body = await req.json().catch(() => ({}))
    const message = typeof body.message === 'string' ? body.message.trim() : ''
    if (body.status !== undefined && !STATUSES.includes(body.status)) {
      return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    }
    if (!message && !body.status) return NextResponse.json({ error: 'Nothing to change' }, { status: 400 })
    if (message.length > 2000) return NextResponse.json({ error: 'Reply is too long (2000 characters max)' }, { status: 400 })
    const ticket: any = await SupportTicket.findById(params.id)
    if (!ticket) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })

    const from = ticket.status
    if (message) ticket.messages.push({ sender: 'admin', message, sentAt: new Date() })
    if (body.status) ticket.status = body.status
    else if (message && ticket.status === 'open') ticket.status = 'in_progress'

    await ticket.save()
    await auditAdmin(req, requireAdmin(req), message ? 'ticket.reply' : 'ticket.status', {
      target: `ticket:${params.id}`,
      summary: `${message ? 'Replied' : 'Status'}${from !== ticket.status ? ` ${from} → ${ticket.status}` : ''} — ${String(ticket.subject || '').slice(0, 80)}`,
    })
    return NextResponse.json(ticket.toObject())
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
