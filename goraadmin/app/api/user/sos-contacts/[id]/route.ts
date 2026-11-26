export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'
import { requireActiveRider, activeDenied } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// DELETE → remove one of the rider's OWN emergency contacts (soft delete).
// Scoped by ownerId: another rider's, a driver's or an admin contact is 404.
export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const a = await requireActiveRider(req); if (!a.ok) return activeDenied(a)
    if (!mongoose.Types.ObjectId.isValid(params.id)) return withCors({ error: 'Contact not found' }, 404)
    await connectDB()
    const res = await SOSContact.findOneAndUpdate(
      { _id: params.id, addedBy: 'user', ownerId: a.id, isActive: true },
      { $set: { isActive: false } },
      { new: true },
    ).lean()
    if (!res) return withCors({ error: 'Contact not found' }, 404)
    return withCors({ success: true })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
