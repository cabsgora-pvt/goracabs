export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import Zone from '@/models/Zone'
import Transaction from '@/models/Transaction'
import WalletTransaction from '@/models/WalletTransaction'
import AdminAudit from '@/models/AdminAudit'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdmin } from '@/lib/admin-audit'
import { cancelRide } from '@/lib/refunds'
import { refundSummaryFor, adminRefundRide } from '@/lib/ride-admin-refund'
import { pushToUserAsync, pushToDriverAsync } from '@/lib/push'

// Admin ride detail (the /rides/{id} page).
//
// GET  → { ride (full document, chat included), rider, driver, zone,
//          walletTx (the rider's wallet rows for this ride), driverTx (driver
//          ledger rows for this ride), refund (lib/ride-admin-refund summary),
//          audit (admin actions on this ride) }
//       Read-only: unlike GET /rides/{id} it never closes an overdue request.
// POST { action: 'cancel', reason }                → lib/refunds cancelRide(id, 'admin', reason)
//      { action: 'refund', amount, reason, key }   → lib/ride-admin-refund adminRefundRide
//      Both need the admin password (sudo window) and are audited.

const notFound = () => NextResponse.json({ error: 'Ride not found' }, { status: 404 })

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return notFound()
    await connectDB()
    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return notFound()
    const id = String(ride._id)
    const [rider, driver, zone, walletTx, driverTx, refund, audit] = await Promise.all([
      ride.riderId ? User.findById(ride.riderId).select('name phone email walletBalance status profilePicUrl createdAt').lean() : null,
      ride.driverId ? Driver.findById(ride.driverId)
        .select('name phone profilePicUrl vehicleModel vehicleNumber vehicleRegistrationNumber selectedVehicleTypeName rating totalRides walletBalance status isOnline currentLat currentLng currentHeading locationUpdatedAt zoneName')
        .lean() : null,
      ride.zoneId ? Zone.findById(ride.zoneId).select('name').lean() : null,
      ride.riderId ? WalletTransaction.find({
        userId: ride.riderId,
        $or: [{ ref: id }, { ref: `void:${id}` }, { ref: { $regex: `^refund:${id}:` } }, { ref: `cod:${id}` }],
      }).sort({ createdAt: 1 }).limit(100).lean() : [],
      Transaction.find({ rideId: ride._id }).sort({ createdAt: 1 }).limit(100).lean(),
      refundSummaryFor(ride),
      AdminAudit.find({ target: { $in: [id, `ride:${id}`] } }).sort({ at: -1 }).limit(50).select('email action summary details at path').lean(),
    ])
    return NextResponse.json({ ride, rider, driver, zone, walletTx, driverTx, refund, audit })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  try {
    if (!mongoose.isValidObjectId(params.id)) return notFound()
    const b: any = await req.json().catch(() => ({}))
    const action = String(b?.action || '')
    if (!['cancel', 'refund'].includes(action)) return NextResponse.json({ error: "action must be 'cancel' or 'refund'" }, { status: 400 })
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    const admin: any = requireAdmin(req)
    await connectDB()

    if (action === 'cancel') {
      const reason = typeof b.reason === 'string' ? b.reason.trim() : ''
      if (reason.length < 3 || reason.length > 300) return NextResponse.json({ error: 'Give a reason (3–300 characters)', code: 'REASON_REQUIRED' }, { status: 400 })
      const before: any = await Ride.findById(params.id).select('status riderId driverId').lean()
      if (!before) return notFound()
      const out = await cancelRide(params.id, 'admin', reason)
      if (out.error) return NextResponse.json({ error: out.error, ...(out.code ? { code: out.code } : {}) }, { status: out.status || 400 })
      if (out.alreadyCancelled) return NextResponse.json({ success: true, alreadyCancelled: true })
      await auditAdmin(req, admin, 'ride.cancel', {
        target: `ride:${params.id}`,
        summary: `Cancelled ride (was ${before.status}): ${reason}`,
        details: { reason, fromStatus: before.status, refundedAmount: out.refundedAmount, refundReview: out.review },
      })
      const ride = out.ride
      pushToUserAsync(ride.riderId, {
        title: 'Ride cancelled', body: `Your ride was cancelled by Gora support: ${reason}`, channelId: 'ride_updates',
        data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'admin' },
      })
      if (ride.driverId) pushToDriverAsync(ride.driverId, {
        title: 'Ride cancelled', body: `This ride was cancelled by Gora support: ${reason}`, channelId: 'ride_updates',
        data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'admin' },
      })
      return NextResponse.json({ success: true, refundedAmount: out.refundedAmount, ...(out.review ? { refundReview: out.review } : {}) })
    }

    // refund
    const out = await adminRefundRide(params.id, { amount: Number(b.amount), reason: String(b.reason || ''), key: String(b.key || '') })
    if (!out.ok) return NextResponse.json({ error: out.error, code: out.code, ...(out.refundable != null ? { refundable: out.refundable } : {}) }, { status: out.status })
    await auditAdmin(req, admin, out.duplicate ? 'ride.refund.duplicate' : 'ride.refund', {
      target: `ride:${params.id}`,
      summary: out.duplicate ? `Repeated refund request (nothing credited)` : `Refunded ₹${out.amount} to the rider's wallet: ${String(b.reason || '').trim()}`,
      details: { amount: out.amount, reason: String(b.reason || '').trim(), paid: out.summary.paid, refundedAfter: out.summary.refunded },
    })
    if (!out.duplicate) {
      const ride: any = await Ride.findById(params.id).select('riderId').lean()
      if (ride?.riderId) pushToUserAsync(ride.riderId, {
        title: 'Refund added to your wallet', body: `₹${out.amount} was refunded to your Gora wallet.`, channelId: 'payments',
        data: { type: 'wallet_refund', rideId: params.id },
      })
    }
    return NextResponse.json({ success: true, amount: out.amount, balance: out.balance, duplicate: !!out.duplicate, refund: out.summary })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
