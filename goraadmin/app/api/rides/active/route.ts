export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { uiPhaseFor } from '@/lib/ride-phase'
import { ACTIVE_STATUSES, blocksNewBooking } from '@/lib/ride-view'

export async function OPTIONS() { return corsOptions() }

const FIELDS = [
  'status', 'service', 'vehicleType', 'pickupAddress', 'dropAddress', 'pickupLat', 'pickupLng', 'dropLat', 'dropLng',
  'fare', 'tip', 'totalFare', 'finalFare', 'paymentMode', 'paymentStatus', 'awaitingPayment', 'amountDue',
  'driverId', 'driverName', 'driverPhone', 'otp', 'scheduledAt', 'departureAt', 'hireStartAt', 'createdAt', 'acceptedAt', 'startedAt',
  'needsReview', 'needsReviewAt', 'reviewReason', 'offeredTo', 'rentalPhase', 'hirePhase', 'deliveryPhase', 'outstationPhase',
  'otpLocked', 'arrivedAt', 'prepaidShortfall', 'prepaidAmount',
].join(' ')

// GET /api/rides/active — the rider's ONE current ride, small: the newest ride
// that is pending / accepted / arrived / ongoing, or one still awaiting
// payment. { ride: {...} | null, blocksBooking }. The rider home polls this
// instead of downloading the whole history (/rides/user).
// `blocksBooking` is lib/ride-view blocksNewBooking (a ride flagged needsReview
// over 30 min ago does not stop a new booking).
export async function GET(req: NextRequest) {
  try {
    const u = requireRider(req) as any
    if (!u?.id) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const rows: any[] = await Ride.find({
      riderId: u.id,
      $or: [
        { status: { $in: ['pending', ...ACTIVE_STATUSES] } },
        { awaitingPayment: true, status: { $ne: 'cancelled' }, paymentStatus: { $ne: 'paid' } },
      ],
    }).sort({ createdAt: -1 }).limit(5).select(FIELDS).lean()
    // Live trips first, then pending, then an unpaid one.
    const rank = (r: any) => (['ongoing', 'arrived', 'accepted'].includes(r.status) ? 0 : r.status === 'pending' ? 1 : 2)
    rows.sort((a, b) => rank(a) - rank(b) || new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
    const r = rows[0]
    if (!r) return withCors({ ride: null, blocksBooking: false })
    const live = ACTIVE_STATUSES.includes(r.status)
    const { _id, offeredTo, driverPhone, ...rest } = r
    const ui = uiPhaseFor(r)
    return withCors({
      ride: {
        id: _id, _id, ...rest,
        ...(live ? { driverPhone } : {}),
        searching: r.status === 'pending',
        uiPhase: ui.phase, uiPhaseLabel: ui.label,
      },
      blocksBooking: rows.some(x => blocksNewBooking(x)),
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
