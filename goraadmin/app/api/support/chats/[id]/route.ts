export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportChat from '@/models/SupportChat'

// GET /api/support/chats/[id] → full chat (marks driver messages as read for admin)
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const chat: any = await SupportChat.findById(params.id)
    if (!chat) return NextResponse.json({ error: 'Chat not found' }, { status: 404 })
    if (chat.adminUnread) { chat.adminUnread = 0; await chat.save() }
    return NextResponse.json({
      _id: chat._id, driverId: chat.driverId, driverName: chat.driverName,
      driverPhone: chat.driverPhone, zoneName: chat.zoneName, messages: chat.messages || [],
    })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

// POST /api/support/chats/[id] → admin sends a message  body: { message }
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { message } = await req.json()
    if (!message || !message.trim()) return NextResponse.json({ error: 'Message required' }, { status: 400 })
    const chat: any = await SupportChat.findById(params.id)
    if (!chat) return NextResponse.json({ error: 'Chat not found' }, { status: 404 })
    chat.messages.push({ sender: 'admin', message: message.trim(), sentAt: new Date() })
    chat.lastMessageAt = new Date()
    chat.driverUnread = (chat.driverUnread || 0) + 1
    chat.adminUnread = 0
    await chat.save()
    return NextResponse.json({ success: true, messages: chat.messages })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
