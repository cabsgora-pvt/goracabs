export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Driver from '@/models/Driver'
import { guardZoneAdmin, logZoneActivity } from '@/lib/zone-admin'

async function ownDriver(id: string, zoneIds: string[]) {
  if (!mongoose.isValidObjectId(id)) return null
  const d: any = await Driver.findById(id).select('-password').lean()
  return d && zoneIds.includes(String(d.zoneId)) ? d : null
}

// GET — one driver of their zone, with documents, for review.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'drivers' })
  if ('denied' in g) return g.denied
  const d = await ownDriver(params.id, g.zoneIds)
  if (!d) return NextResponse.json({ error: 'Driver not found in your zone' }, { status: 404 })
  return NextResponse.json({
    driver: {
      _id: d._id, name: d.name, phone: d.phone, email: d.email, status: d.status, isOnline: d.isOnline,
      selectedVehicleTypeName: d.selectedVehicleTypeName, vehicleNumber: d.vehicleNumber, vehicleModel: d.vehicleModel,
      profilePicUrl: d.profilePicUrl, rating: d.rating, totalRides: d.totalRides, rejectionReason: d.rejectionReason,
      documents: (d.documents || []).map((x: any) => ({ type: x.type, status: x.status, frontUrl: x.frontUrl || x.fileUrl, backUrl: x.backUrl })),
      createdAt: d.createdAt,
    },
  })
}

// POST { action: 'approve' | 'reject' | 'block' | 'unblock', reason? }
// The same status changes the super admin makes, limited to their own zone.
// Wallet, documents and deletion stay with the super admin.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const g = await guardZoneAdmin(req, { feature: 'drivers', write: true })
  if ('denied' in g) return g.denied
  try {
    const d = await ownDriver(params.id, g.zoneIds)
    if (!d) return NextResponse.json({ error: 'Driver not found in your zone' }, { status: 404 })
    const { action, reason } = await req.json()
    let set: any
    switch (action) {
      case 'approve': set = { status: 'approved', rejectionReason: '' }; break
      case 'reject': set = { status: 'rejected', rejectionReason: String(reason || '').slice(0, 300) }; break
      // A blocked driver is also taken offline so dispatch stops offering them.
      case 'block': set = { status: 'blocked', isOnline: false }; break
      case 'unblock':
        if (d.status !== 'blocked') return NextResponse.json({ error: 'Driver is not blocked' }, { status: 400 })
        set = { status: 'approved' }; break
      default: return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
    }
    await Driver.updateOne({ _id: d._id }, { $set: set })
    await logZoneActivity(g.admin._id, g.actor, `driver.${action}`, { driver: d.name, phone: d.phone, from: d.status, to: set.status, reason: set.rejectionReason || undefined })
    return NextResponse.json({ success: true, status: set.status })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
