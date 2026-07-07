export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

// In-ride chat. Accepts either a rider or a driver token (both are Bearer JWTs).
// GET  → { messages: [{ sender, text, createdAt }] }
// POST { sender: 'user'|'driver', text } → appends a message.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!requireAuth(req)) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('messages').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ messages: ride.messages || [] })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!requireAuth(req)) return withCors({ error: 'Unauthorized' }, 401)
    const { sender, text } = await req.json()
    if ((sender !== 'user' && sender !== 'driver') || !text || !text.toString().trim()) {
      return withCors({ error: 'sender and text are required' }, 400)
    }
    await connectDB()
    const msg = { sender, text: text.toString().trim().slice(0, 1000), createdAt: new Date() }
    const ride: any = await Ride.findByIdAndUpdate(
      params.id,
      { $push: { messages: msg } },
      { new: true }
    ).select('messages').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    return withCors({ success: true, messages: ride.messages || [] })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
