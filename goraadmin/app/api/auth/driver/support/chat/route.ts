export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SupportChat from '@/models/SupportChat'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

async function getOrCreate(driverId: string) {
  let chat: any = await SupportChat.findOne({ driverId })
  if (!chat) {
    const driver: any = await Driver.findById(driverId).select('name phone zoneName').lean()
    chat = await SupportChat.create({
      driverId, driverName: driver?.name || 'Driver', driverPhone: driver?.phone || '',
      zoneName: driver?.zoneName || '', messages: [], lastMessageAt: new Date(),
    })
  }
  return chat
}

// GET → driver's support chat (marks admin replies as read on the driver side)
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const chat: any = await getOrCreate(String(payload.id))
    if (chat.driverUnread) { chat.driverUnread = 0; await chat.save() }
    return withCors({ messages: chat.messages || [] })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST → driver sends a message  body: { message }
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { message } = await req.json()
    if (!message || !message.trim()) return withCors({ error: 'Message required' }, 400)

    await connectDB()
    const chat: any = await getOrCreate(String(payload.id))
    chat.messages.push({ sender: 'driver', message: message.trim(), sentAt: new Date() })
    chat.lastMessageAt = new Date()
    chat.adminUnread = (chat.adminUnread || 0) + 1
    chat.driverUnread = 0
    await chat.save()
    return withCors({ success: true, messages: chat.messages })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
