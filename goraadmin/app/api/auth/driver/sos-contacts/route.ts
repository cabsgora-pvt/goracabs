export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Driver-facing SOS contacts.
//
// The driver app's SOS screen was populated from mockSOSContacts — invented
// names and numbers on a safety screen, and "deleting" one only mutated a local
// list. The SOSContact model already supported both cases via `addedBy`, so
// this exposes them properly:
//
//   • admin contacts (addedBy 'admin', no owner)  → shown to every driver,
//     read-only, these are the fleet/control-room numbers
//   • the driver's own contacts (addedBy 'driver') → theirs to add and remove
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const driverId = String((payload as any).id)

    await connectDB()
    const rows: any[] = await SOSContact.find({
      isActive: true,
      $or: [
        { addedBy: 'admin' },
        { addedBy: 'driver', ownerId: driverId },
      ],
    }).sort({ addedBy: 1, createdAt: 1 }).lean()

    return withCors({
      contacts: rows.map(c => ({
        id: String(c._id),
        name: c.name || '',
        phone: c.phone || '',
        relation: c.relation || '',
        // Admin-provided numbers cannot be deleted by the driver.
        editable: c.addedBy === 'driver' && String(c.ownerId) === driverId,
      })),
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

// POST { name, phone, relation } → add one of the driver's own contacts.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const driverId = String((payload as any).id)

    const b = await req.json()
    const name = (b.name || '').toString().trim()
    const phone = (b.phone || '').toString().trim()
    if (!name || !phone) return withCors({ error: 'Name and phone are required' }, 400)

    await connectDB()
    // A short list keeps the alert fan-out meaningful.
    const mine = await SOSContact.countDocuments({ addedBy: 'driver', ownerId: driverId, isActive: true })
    if (mine >= 5) return withCors({ error: 'You can keep up to 5 emergency contacts' }, 400)

    const c: any = await SOSContact.create({
      name, phone,
      relation: (b.relation || '').toString().trim(),
      addedBy: 'driver',
      ownerId: driverId,
      isActive: true,
    })

    return withCors({
      contact: { id: String(c._id), name: c.name, phone: c.phone, relation: c.relation, editable: true },
    }, 201)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
