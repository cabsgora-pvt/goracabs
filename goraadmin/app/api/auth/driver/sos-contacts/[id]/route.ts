export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// DELETE → remove one of the driver's OWN contacts.
// Scoped by ownerId so a driver cannot delete another driver's contact, and
// admin/control-room numbers cannot be removed from the app at all.
export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const driverId = String((payload as any).id)

    await connectDB()
    const res = await SOSContact.findOneAndUpdate(
      { _id: params.id, addedBy: 'driver', ownerId: driverId },
      { $set: { isActive: false } },
      { new: true },
    ).lean()

    if (!res) return withCors({ error: 'Contact not found' }, 404)
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
