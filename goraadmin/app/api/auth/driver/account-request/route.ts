export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import AccountRequest from '@/models/AccountRequest'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { DELETE_REASONS, publicRequest } from '@/lib/account-requests'

export async function OPTIONS() { return corsOptions() }

// GET  → { reasons, requests }
// POST { kind: 'delete', reason, note? }
//      { kind: 'zone_change', toZoneId, note? }   — the admin approves the move
// DELETE ?id= → withdraw a pending request
export async function GET(req: NextRequest) {
  const p: any = requireDriverAuth(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  await connectDB()
  const rows = await AccountRequest.find({ userType: 'driver', userId: p.id }).sort({ createdAt: -1 }).limit(10).lean()
  return withCors({ reasons: DELETE_REASONS, requests: rows.map(publicRequest) })
}

export async function POST(req: NextRequest) {
  try {
    const p: any = requireDriverAuth(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
    const b = await req.json().catch(() => ({}))
    await connectDB()
    const d: any = await Driver.findById(p.id).select('name phone status zoneId zoneName').lean()
    if (!d || d.status === 'deleted') return withCors({ error: 'Driver not found' }, 404)
    const base = { userType: 'driver', userId: p.id, name: d.name || '', phone: d.phone || '', note: String(b.note || '').trim().slice(0, 500) }

    if (b.kind === 'delete') {
      const reason = String(b.reason || '').trim().slice(0, 120)
      if (!reason) return withCors({ error: 'Please choose a reason' }, 400)
      const existing = await AccountRequest.findOne({ userType: 'driver', userId: p.id, kind: 'delete', status: 'pending' }).lean()
      if (existing) return withCors({ success: true, request: publicRequest(existing), already: true })
      const r = await AccountRequest.create({ ...base, kind: 'delete', reason })
      return withCors({ success: true, request: publicRequest(r.toObject()) }, 201)
    }

    if (b.kind === 'zone_change') {
      const toZoneId = String(b.toZoneId || '')
      if (!mongoose.isValidObjectId(toZoneId)) return withCors({ error: 'Choose a zone' }, 400)
      const z: any = await Zone.findById(toZoneId).select('name isActive').lean()
      if (!z || z.isActive === false) return withCors({ error: 'That zone is not available' }, 400)
      if (String(d.zoneId || '') === toZoneId) return withCors({ error: 'You are already in this zone' }, 400)
      // One open zone request at a time: a new choice replaces the old one.
      await AccountRequest.updateMany({ userType: 'driver', userId: p.id, kind: 'zone_change', status: 'pending' },
        { $set: { status: 'cancelled', handledAt: new Date(), handledBy: 'self' } })
      const r = await AccountRequest.create({
        ...base, kind: 'zone_change', reason: 'Zone change', toZoneId, toZoneName: z.name,
        fromZoneId: d.zoneId || '', fromZoneName: d.zoneName || '',
      })
      return withCors({ success: true, request: publicRequest(r.toObject()) }, 201)
    }
    return withCors({ error: 'Unknown request' }, 400)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

export async function DELETE(req: NextRequest) {
  const p: any = requireDriverAuth(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  const id = req.nextUrl.searchParams.get('id') || ''
  await connectDB()
  const r = await AccountRequest.findOneAndUpdate({ _id: id, userType: 'driver', userId: p.id, status: 'pending' },
    { $set: { status: 'cancelled', handledAt: new Date(), handledBy: 'self' } }, { new: true }).lean().catch(() => null)
  if (!r) return withCors({ error: 'Request not found' }, 404)
  return withCors({ success: true })
}
