export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import User from '@/models/User'
import AccountRequest from '@/models/AccountRequest'
import { requireAuth, isAdminPayload } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { DELETE_REASONS, publicRequest } from '@/lib/account-requests'

export async function OPTIONS() { return corsOptions() }

// GET  → { reasons, requests } — the rider's own requests (latest 10).
// POST { kind: 'delete', reason, note? } → asks the admin to delete the account.
// DELETE ?id= → withdraw a pending request.
function rider(req: NextRequest) {
  const p: any = requireAuth(req)
  return p?.id && !isAdminPayload(p) && p.type !== 'driver' ? p : null
}

export async function GET(req: NextRequest) {
  const p = rider(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  await connectDB()
  const rows = await AccountRequest.find({ userType: 'rider', userId: p.id }).sort({ createdAt: -1 }).limit(10).lean()
  return withCors({ reasons: DELETE_REASONS, requests: rows.map(publicRequest) })
}

export async function POST(req: NextRequest) {
  try {
    const p = rider(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
    const b = await req.json().catch(() => ({}))
    if (b.kind !== 'delete') return withCors({ error: 'Unknown request' }, 400)
    const reason = String(b.reason || '').trim().slice(0, 120)
    if (!reason) return withCors({ error: 'Please choose a reason' }, 400)
    await connectDB()
    const u: any = await User.findById(p.id).select('name phone status').lean()
    if (!u || u.status === 'deleted') return withCors({ error: 'Account not found' }, 404)
    const existing = await AccountRequest.findOne({ userType: 'rider', userId: p.id, kind: 'delete', status: 'pending' }).lean()
    if (existing) return withCors({ success: true, request: publicRequest(existing), already: true })
    const r = await AccountRequest.create({
      userType: 'rider', userId: p.id, name: u.name || '', phone: u.phone || '', kind: 'delete',
      reason, note: String(b.note || '').trim().slice(0, 500),
    })
    return withCors({ success: true, request: publicRequest(r.toObject()) }, 201)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

export async function DELETE(req: NextRequest) {
  const p = rider(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  const id = req.nextUrl.searchParams.get('id') || ''
  await connectDB()
  const r = await AccountRequest.findOneAndUpdate({ _id: id, userType: 'rider', userId: p.id, status: 'pending' },
    { $set: { status: 'cancelled', handledAt: new Date(), handledBy: 'self' } }, { new: true }).lean().catch(() => null)
  if (!r) return withCors({ error: 'Request not found' }, 404)
  return withCors({ success: true })
}
