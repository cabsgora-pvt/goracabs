export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SupportChat from '@/models/SupportChat'
import { guardAdmin } from '@/lib/admin-guard'

// GET /api/support/chats → list of driver chats for the admin panel
export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const chats: any[] = await SupportChat.find({}).sort({ lastMessageAt: -1 }).limit(200).lean()
    const list = chats.map((c) => {
      const last = c.messages?.length ? c.messages[c.messages.length - 1] : null
      return {
        _id: c._id,
        driverId: c.driverId,
        driverName: c.driverName || 'Driver',
        driverPhone: c.driverPhone || '',
        zoneName: c.zoneName || '',
        lastMessage: last?.message || '',
        lastSender: last?.sender || '',
        lastMessageAt: c.lastMessageAt,
        adminUnread: c.adminUnread || 0,
      }
    })
    return NextResponse.json({ chats: list })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
