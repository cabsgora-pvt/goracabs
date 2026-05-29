import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportTicket from '@/models/SupportTicket'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ticket = await SupportTicket.findById(params.id).lean()
    if (!ticket) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })
    return NextResponse.json(ticket)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const ticket = await SupportTicket.findById(params.id)
    if (!ticket) return NextResponse.json({ error: 'Ticket not found' }, { status: 404 })

    if (body.message) {
      ticket.messages.push({
        sender: body.sender || 'admin',
        message: body.message,
        sentAt: new Date(),
      })
    }
    if (body.status) {
      ticket.status = body.status
    } else if (body.message) {
      ticket.status = 'in_progress'
    }

    await ticket.save()
    return NextResponse.json(ticket.toObject())
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
