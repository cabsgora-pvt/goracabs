export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import AccountRequest from '@/models/AccountRequest'
import User from '@/models/User'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'

// PUT { action: 'approve' | 'reject', note? }
//   delete + approve      → account closed: personal data cleared, the phone
//                           freed so the person can sign up again later. Ride
//                           and money history stay (needed for accounts).
//   zone_change + approve → driver moved to the requested zone (logged).
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    const admin: any = requireAdmin(req)
    const b = await req.json().catch(() => ({}))
    const action = b.action
    if (action !== 'approve' && action !== 'reject') return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
    await connectDB()
    const r: any = await AccountRequest.findById(params.id)
    if (!r) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    if (r.status !== 'pending') return NextResponse.json({ error: `Already ${r.status}` }, { status: 409 })
    const by = admin?.email || 'admin'
    const note = String(b.note || '').trim().slice(0, 500)

    if (action === 'approve' && r.kind === 'delete') {
      const Model: any = r.userType === 'driver' ? Driver : User
      const doc: any = await Model.findById(r.userId)
      if (!doc) return NextResponse.json({ error: 'Account no longer exists' }, { status: 404 })
      if (r.userType === 'driver') {
        const busy = await Ride.exists({ driverId: doc._id, status: { $in: ['accepted', 'arrived', 'ongoing'] } })
        if (busy) return NextResponse.json({ error: 'Driver has a ride in progress — try after it ends' }, { status: 409 })
      } else {
        const busy = await Ride.exists({ riderId: doc._id, status: { $in: ['pending', 'accepted', 'arrived', 'ongoing'] } })
        if (busy) return NextResponse.json({ error: 'Rider has a ride in progress — try after it ends' }, { status: 409 })
      }
      const stamp = Date.now()
      doc.status = 'deleted'
      doc.deletedAt = new Date()
      doc.name = r.userType === 'driver' ? 'Deleted driver' : 'Deleted user'
      doc.phone = `deleted_${stamp}_${doc.phone || ''}`.slice(0, 60)
      doc.email = ''
      if (r.userType === 'driver') { doc.isOnline = false; doc.fcmToken = '' }
      await doc.save()
    }

    if (action === 'approve' && r.kind === 'zone_change') {
      const z: any = await Zone.findById(r.toZoneId).select('name').lean()
      if (!z) return NextResponse.json({ error: 'Zone no longer exists' }, { status: 404 })
      const d: any = await Driver.findById(r.userId).select('zoneId zoneName').lean()
      if (!d) return NextResponse.json({ error: 'Driver no longer exists' }, { status: 404 })
      await Driver.updateOne({ _id: r.userId }, {
        $set: { zoneId: String(z._id), zoneName: z.name },
        $push: { zoneHistory: { from: d.zoneId || '', fromName: d.zoneName || '', to: String(z._id), toName: z.name, by: `request:${by}`, at: new Date() } },
      })
    }

    r.status = action === 'approve' ? 'approved' : 'rejected'
    r.adminNote = note
    r.handledAt = new Date()
    r.handledBy = by
    await r.save()
    return NextResponse.json({ success: true, request: r.toObject() })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
