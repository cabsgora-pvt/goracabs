export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import SupportTicket from '@/models/SupportTicket'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → driver's own tickets
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const tickets = await SupportTicket.find({ driverId: payload.id }).sort({ updatedAt: -1 }).limit(50).lean()
    return withCors({ tickets })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}

// POST → create a ticket  body: { subject, category?, message }
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { subject, category, message } = await req.json()
    if (!subject || !message) return withCors({ error: 'Subject and message are required' }, 400)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).select('name phone zoneName').lean()

    const ticket = await SupportTicket.create({
      driverId: payload.id,
      role: 'driver',
      userName: driver?.name || 'Driver',
      driverPhone: driver?.phone || '',
      zoneName: driver?.zoneName || '',
      subject,
      category: category || 'general',
      status: 'open',
      messages: [{ sender: 'driver', message, sentAt: new Date() }],
    })
    return withCors({ success: true, ticket })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
