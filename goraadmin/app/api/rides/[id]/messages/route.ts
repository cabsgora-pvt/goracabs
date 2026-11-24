export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { withCors, corsOptions } from '@/lib/cors'
import { pushToUserAsync, pushToDriverAsync } from '@/lib/push'
import { rideActor } from '@/lib/ride-view'

export async function OPTIONS() {
  return corsOptions()
}

// In-ride chat. Only the ride's rider, its assigned driver, or an admin (read
// only) may use it. The sender is taken from the TOKEN — a body `sender` is
// ignored — so neither side can write as the other.
// GET  → { messages: [{ sender, text, createdAt }] }
// POST { text } → appends a message as 'user' (rider token) or 'driver'.
const CHAT_STATUSES = ['accepted', 'arrived', 'ongoing']

async function load(req: NextRequest, id: string) {
  if (!mongoose.isValidObjectId(id)) return { res: withCors({ error: 'Ride not found' }, 404) }
  const ride: any = await Ride.findById(id).select('messages riderId driverId riderName driverName status').lean()
  if (!ride) return { res: withCors({ error: 'Ride not found' }, 404) }
  const who = rideActor(req, ride)
  if (!('actor' in who)) return { res: withCors({ error: who.error, code: who.code }, who.status) }
  return { ride, actor: who.actor }
}

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const r = await load(req, params.id)
    if (r.res) return r.res
    return withCors({ messages: r.ride.messages || [] })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const { text } = await req.json().catch(() => ({}))
    if (!text || !text.toString().trim()) return withCors({ error: 'text is required' }, 400)
    await connectDB()
    const r = await load(req, params.id)
    if (r.res) return r.res
    if (r.actor.role === 'admin') return withCors({ error: 'Admins can read this chat but not write in it' }, 403)
    if (!CHAT_STATUSES.includes(r.ride.status)) return withCors({ error: 'Chat is closed for this ride', code: 'CHAT_CLOSED' }, 409)
    const sender = r.actor.role === 'driver' ? 'driver' : 'user'
    const msg = { sender, text: text.toString().trim().slice(0, 1000), createdAt: new Date() }
    const ride: any = await Ride.findByIdAndUpdate(
      params.id,
      { $push: { messages: { $each: [msg], $slice: -500 } } },
      { new: true }
    ).select('messages riderId driverId riderName driverName').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)

    // Chat is poll-based on both sides, so without this a message is only seen
    // if the other party happens to have the chat screen open.
    if (sender === 'user') {
      pushToDriverAsync(ride.driverId, {
        title: ride.riderName || 'Rider',
        body: msg.text,
        channelId: 'ride_chat',
        data: { type: 'ride_message', rideId: String(params.id), sender: 'user' },
      })
    } else {
      pushToUserAsync(ride.riderId, {
        title: ride.driverName || 'Driver',
        body: msg.text,
        channelId: 'ride_chat',
        data: { type: 'ride_message', rideId: String(params.id), sender: 'driver' },
      })
    }

    return withCors({ success: true, messages: ride.messages || [] })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
