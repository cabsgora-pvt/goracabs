export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import AccountRequest from '@/models/AccountRequest'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import { softDeleteAccount } from '@/lib/account-delete'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'

// PUT { action: 'approve' | 'reject', note? }
//   delete + approve      → account closed: personal data cleared, the phone
//                           freed so the person can sign up again later. Ride
//                           and money history stay (needed for accounts).
//   zone_change + approve → driver moved to the requested zone (logged).
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
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
      // Shared soft delete (lib/account-delete): refuses during a live ride,
      // blanks PII, frees the phone, keeps ride and money history.
      const del = await softDeleteAccount(r.userType === 'driver' ? 'driver' : 'rider', String(r.userId))
      if (!del.ok) return NextResponse.json({ error: del.error }, { status: del.status })
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
