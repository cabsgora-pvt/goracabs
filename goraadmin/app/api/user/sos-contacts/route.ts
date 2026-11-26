export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'
import { requireActiveRider, activeDenied } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { normalizePhone } from '@/lib/phone'

export async function OPTIONS() { return corsOptions() }

// Rider-facing emergency contacts (the rider app's SOS screen).
//
// The rider app kept them only in SharedPreferences, so they were lost on a
// reinstall or a new phone. These are the rider's OWN contacts
// (addedBy 'user', ownerId = rider id); admin/control-room contacts are not
// mixed in here - the rider app's SOS screen raises the alert to Gora itself.
const MAX_CONTACTS = 5

function view(c: any) {
  return { id: String(c._id), name: c.name || '', phone: c.phone || '', relation: c.relation || '' }
}

// GET → { contacts: [{id, name, phone, relation}] } oldest first.
export async function GET(req: NextRequest) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    await connectDB()
    const rows: any[] = await SOSContact.find({ addedBy: 'user', ownerId: a.id, isActive: true })
      .sort({ createdAt: 1 }).limit(MAX_CONTACTS).lean()
    return withCors({ contacts: rows.map(view), max: MAX_CONTACTS })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}

// POST { name, phone, relation? } → 201 { contact }. The phone must be an
// Indian mobile (stored as 10 digits). A number already on the list returns
// that contact (200, duplicate: true) instead of a second copy, so the app can
// re-send its local list safely. 400 at the 5-contact limit.
export async function POST(req: NextRequest) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    let b: any
    try { b = await req.json() } catch { return withCors({ error: 'Invalid request' }, 400) }
    if (!b || typeof b !== 'object') return withCors({ error: 'Invalid request' }, 400)
    const name = String(b.name ?? '').trim().slice(0, 60)
    const relation = String(b.relation ?? '').trim().slice(0, 40)
    const phone = normalizePhone(b.phone)
    if (!name) return withCors({ error: 'Name is required' }, 400)
    if (!phone) return withCors({ error: 'Enter a valid 10-digit mobile number', code: 'INVALID_PHONE' }, 400)

    await connectDB()
    const existing: any = await SOSContact.findOne({ addedBy: 'user', ownerId: a.id, isActive: true, phone }).lean()
    if (existing) return withCors({ contact: view(existing), duplicate: true })

    const mine = await SOSContact.countDocuments({ addedBy: 'user', ownerId: a.id, isActive: true })
    if (mine >= MAX_CONTACTS) {
      return withCors({ error: `You can keep up to ${MAX_CONTACTS} emergency contacts`, code: 'LIMIT_REACHED' }, 400)
    }
    const c: any = await SOSContact.create({ name, phone, relation, addedBy: 'user', ownerId: a.id, isActive: true })
    return withCors({ contact: view(c) }, 201)
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
