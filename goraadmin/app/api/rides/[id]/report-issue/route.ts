export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireActiveRider, requireAdmin } from '@/lib/auth'
import { guardAdmin } from '@/lib/admin-guard'
import { auditAdmin } from '@/lib/admin-audit'
import { limitHit } from '@/lib/rate-limit'
import { cancelRide } from '@/lib/refunds'
import { openReviewTicket } from '@/lib/dispatch'
import { pushToDriverAsync } from '@/lib/push'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

const KINDS = ['driver_unreachable', 'driver_not_arrived', 'other'] as const
const REPORTABLE = ['pending', 'accepted', 'arrived', 'ongoing']
const REPORT_RATE = { LIMIT: 5, WINDOW_MS: 10 * 60_000 }

// POST /api/rides/{id}/report-issue
//
// Rider (the ride's rider; blocked / deleted accounts refused):
//   { kind: 'driver_unreachable' | 'driver_not_arrived' | 'other', note? }
//   → the ride is flagged needsReview (an admin ticket is opened), the report
//     kept in issueReports. 'driver_unreachable' on an accepted / arrived ride
//     (not one already under way) also CANCELS it as the system — no
//     cancellation fee — and refunds anything prepaid (lib/refunds cancelRide).
//   ← { success, needsReview: true, cancelled?, status }
//   Rate limited: REPORT_RATE per rider (429 RATE_LIMITED).
//
// Admin: { action: 'resolve', note? } → clears needsReview (reviewResolvedAt /
//   reviewResolvedBy / reviewNote), audited. The sweep leaves a resolved ride
//   alone for an hour.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)
    const b = await req.json().catch(() => ({}))

    // ── Admin: resolve ──
    if (requireAdmin(req)) {
      const denied = await guardAdmin(req); if (denied) return denied
      const admin: any = requireAdmin(req)
      if (b?.action !== 'resolve') return withCors({ error: "action must be 'resolve'" }, 400)
      await connectDB()
      const note = typeof b.note === 'string' ? b.note.trim().slice(0, 500) : ''
      const r: any = await Ride.findOneAndUpdate(
        { _id: params.id },
        { $set: { needsReview: false, reviewResolvedAt: new Date(), reviewResolvedBy: String(admin.email || admin.id), reviewNote: note }, $unset: { stuckSince: 1 } },
        { new: true },
      ).select('_id status needsReview reviewReason').lean()
      if (!r) return withCors({ error: 'Ride not found' }, 404)
      await auditAdmin(req, admin, 'ride.review.resolve', { target: `ride:${params.id}`, summary: `Resolved review (${r.reviewReason || 'n/a'})`, details: { note } })
      return withCors({ success: true, needsReview: false, status: r.status })
    }

    // ── Rider: report ──
    const act = await requireActiveRider(req)
    if (!act.ok) return withCors({ error: act.error, code: act.code }, act.status)
    const kind = String(b?.kind || '')
    if (!(KINDS as readonly string[]).includes(kind)) return withCors({ error: `kind must be one of ${KINDS.join(', ')}`, code: 'INVALID_KIND' }, 400)
    const note = typeof b.note === 'string' ? b.note.trim().slice(0, 500) : ''
    if (!(await limitHit(`report-issue:${act.id}`, REPORT_RATE.LIMIT, REPORT_RATE.WINDOW_MS))) {
      return withCors({ error: 'Too many reports. Please wait a few minutes or call support.', code: 'RATE_LIMITED' }, 429)
    }
    await connectDB()
    const ride: any = await Ride.findById(params.id).select('riderId riderName driverId status service needsReview').lean()
    if (!ride) return withCors({ error: 'Ride not found' }, 404)
    if (String(ride.riderId || '') !== act.id) return withCors({ error: 'Not your ride', code: 'NOT_PARTICIPANT' }, 403)
    if (!REPORTABLE.includes(ride.status)) {
      return withCors({ error: `This ride is ${ride.status}; contact support from Help`, code: 'NOT_ACTIVE', status: ride.status }, 409)
    }

    const now = new Date()
    await Ride.updateOne({ _id: ride._id }, {
      $push: { issueReports: { $each: [{ kind, note, by: 'rider', at: now }], $slice: -20 } },
      $set: { needsReview: true, reviewReason: `rider_${kind}`, ...(ride.needsReview ? {} : { needsReviewAt: now }) },
    })

    let cancelled = false
    if (kind === 'driver_unreachable' && ['accepted', 'arrived'].includes(ride.status)) {
      // Claim the ride first: /start refuses a ride carrying this, so the trip
      // cannot begin between this check and the cancel below.
      const claim = await Ride.updateOne(
        { _id: ride._id, status: { $in: ['accepted', 'arrived'] }, unreachableCancelAt: null },
        { $set: { unreachableCancelAt: now } },
      )
      if (claim.modifiedCount) {
        const out: any = await cancelRide(ride._id, 'system', 'driver_unreachable')
        cancelled = !!out?.ride && !out.alreadyCancelled && !out.error
        if (cancelled && ride.driverId) {
          pushToDriverAsync(ride.driverId, {
            title: 'Ride cancelled',
            body: 'The rider could not reach you, so this ride was cancelled.',
            channelId: 'ride_updates',
            data: { type: 'ride_cancelled', rideId: String(ride._id), cancelledBy: 'system', reason: 'driver_unreachable' },
          })
        }
      }
    }
    await openReviewTicket(ride, `Rider reported: ${kind.replace(/_/g, ' ')}${cancelled ? ' (ride cancelled)' : ''}`,
      `Ride status when reported: ${ride.status}.${note ? ` Rider's note: ${note}` : ''}`)

    const after: any = await Ride.findById(ride._id).select('status').lean()
    return withCors({ success: true, needsReview: true, ...(cancelled ? { cancelled: true, cancellationFee: 0 } : {}), status: after?.status })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
