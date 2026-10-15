export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import SupportTicket from '@/models/SupportTicket'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { reverseGeocode } from '@/lib/geocode'
import { pushToUserAsync } from '@/lib/push'

export async function OPTIONS() { return corsOptions() }

// POST /api/rides/{id}/toll — tolls on an outstation trip.
//
// Driver (the ride's assigned driver, while the trip is under way):
//   { action: 'add', amount, clientRef, source?: 'prompt' | 'manual', lat?, lng? }
//   { action: 'remove', tollId }
// Rider (the ride's own rider, during or after the trip):
//   { action: 'report', tollId, reason: 'no_toll' | 'wrong_amount' | 'other', note? }
//
// Once the driver has ended the trip (payment requested, or completed) the list
// is frozen, so the bill the rider settles cannot change under them. A report
// does not change the bill either: it opens a support ticket, and the toll is
// marked as reported for everyone who sees it.
//
// Tolls are a reimbursement the rider pays the driver directly at the end of
// the trip. They are never added to fare/totalFare and never touch commission
// or any wallet: /complete does not read them.
//
// Each change is ONE atomic update whose filter carries every precondition, so
// two taps, a retry and a trip ending at the same moment cannot race:
// `tollCharge` always equals the sum of `tolls`.

const MAX_TOLL_RUPEES = 2000    // a single plaza; long closed expressways stay under this
const MAX_TOLL_ENTRIES = 30
const REASONS: Record<string, string> = {
  no_toll: 'No toll was paid here',
  wrong_amount: 'The amount is wrong',
  other: 'Other',
}
const MAX_NOTE = 300

const ENTRY_FIELDS = (t: any) => ({
  id: String(t._id),
  amount: t.amount,
  at: t.at,
  source: t.source,
  place: t.place || '',
  reported: !!t.reportedAt,
  reportReason: t.reportReason || null,
})

function body(ride: any, extra: Record<string, unknown> = {}) {
  const tolls = (ride?.tolls || []).map(ENTRY_FIELDS)
  return withCors({ success: true, tolls, tollCharge: ride?.tollCharge || 0, ...extra })
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const who = requireDriverAuth(req) as any
    if (!who?.id) return withCors({ error: 'Unauthorized' }, 401)
    if (!mongoose.isValidObjectId(params.id)) return withCors({ error: 'Ride not found' }, 404)

    let b: any
    try { b = await req.json() } catch { return withCors({ error: 'Invalid request' }, 400) }
    const action = String(b?.action || '')
    if (!['add', 'remove', 'report'].includes(action)) return withCors({ error: 'Unknown action' }, 400)

    // Drivers add and remove; only the rider reports. The same bearer token
    // format serves both apps, so the token's type decides.
    if (action === 'report' ? who.type !== 'user' : who.type !== 'driver') {
      return withCors({ error: 'Unauthorized' }, 401)
    }

    await connectDB()
    if (action === 'report') return report(params.id, who.id, b)

    // Everything that must hold for the toll list to change.
    const open = {
      _id: params.id,
      driverId: who.id,
      service: 'outstation',
      status: 'ongoing',
      awaitingPayment: { $ne: true },
    }

    if (action === 'add') {
      const amount = Math.round(Number(b.amount))
      if (!Number.isFinite(amount) || amount < 1 || amount > MAX_TOLL_RUPEES) {
        return withCors({ error: `Toll must be between ₹1 and ₹${MAX_TOLL_RUPEES}` }, 400)
      }
      const clientRef = typeof b.clientRef === 'string' ? b.clientRef.trim() : ''
      if (!clientRef || clientRef.length > 64) return withCors({ error: 'clientRef required' }, 400)
      const source = b.source === 'prompt' ? 'prompt' : 'manual'
      const entry: any = { amount, at: new Date(), source, clientRef, place: '' }
      if (typeof b.lat === 'number' && typeof b.lng === 'number') {
        entry.lat = b.lat
        entry.lng = b.lng
        // Where it was paid, for the bill. Best effort: a toll is never refused
        // because the address could not be looked up.
        entry.place = await reverseGeocode(b.lat, b.lng)
      }

      const ride: any = await Ride.findOneAndUpdate(
        {
          ...open,
          'tolls.clientRef': { $ne: clientRef },
          // Fewer than MAX entries: the (MAX-1)th index does not exist yet.
          [`tolls.${MAX_TOLL_ENTRIES - 1}`]: { $exists: false },
        },
        { $push: { tolls: entry }, $inc: { tollCharge: amount } },
        { returnDocument: 'after' },
      ).lean()
      if (!ride) return explain(params.id, who.id, clientRef)

      // The rider hears about each toll as it is added, not first on the bill.
      pushToUserAsync(ride.riderId, {
        title: 'Toll added to your trip',
        body: `₹${amount}${entry.place ? ` at ${entry.place}` : ''}. You pay tolls to your driver. Tap to view or report it.`,
        channelId: 'ride_updates',
        data: { type: 'toll_added', rideId: String(ride._id), amount: String(amount) },
      })
      return body(ride)
    }

    // remove
    const tollId = String(b.tollId || '')
    if (!mongoose.isValidObjectId(tollId)) return withCors({ error: 'Toll not found' }, 404)
    const current: any = await Ride.findOne({ ...open, 'tolls._id': tollId }).select('tolls').lean()
    const target = current?.tolls?.find((t: any) => String(t._id) === tollId)
    if (!target) return explain(params.id, who.id, null, tollId)
    const ride = await Ride.findOneAndUpdate(
      { ...open, 'tolls._id': tollId },
      { $pull: { tolls: { _id: tollId } }, $inc: { tollCharge: -target.amount } },
      { returnDocument: 'after' },
    ).lean()
    if (ride) return body(ride)
    return explain(params.id, who.id, null, tollId)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

/**
 * The rider disputes one toll. Marked on the toll first — atomically, so it can
 * only be reported once however often the button is pressed — then a support
 * ticket is opened for the team to review. If the ticket cannot be created the
 * mark is taken off again, so a report never exists without its ticket.
 */
async function report(rideId: string, riderId: string, b: any) {
  const tollId = String(b.tollId || '')
  if (!mongoose.isValidObjectId(tollId)) return withCors({ error: 'Toll not found' }, 404)
  const reason = String(b.reason || '')
  if (!REASONS[reason]) return withCors({ error: 'Choose a reason' }, 400)
  const note = typeof b.note === 'string' ? b.note.trim().slice(0, MAX_NOTE) : ''

  const reportedAt = new Date()
  const ride: any = await Ride.findOneAndUpdate(
    {
      _id: rideId,
      riderId,
      service: 'outstation',
      // During the trip, or after it — never on a cancelled one.
      status: { $in: ['ongoing', 'completed'] },
      tolls: { $elemMatch: { _id: tollId, reportedAt: { $exists: false } } },
    },
    { $set: { 'tolls.$.reportedAt': reportedAt, 'tolls.$.reportReason': reason, 'tolls.$.reportNote': note } },
    { returnDocument: 'after' },
  ).lean()

  if (!ride) {
    const r: any = await Ride.findById(rideId).select('riderId service status tolls tollCharge').lean()
    if (!r) return withCors({ error: 'Ride not found' }, 404)
    if (!r.riderId || String(r.riderId) !== String(riderId)) return withCors({ error: 'Not your ride' }, 403)
    if (r.service !== 'outstation') return withCors({ error: 'Tolls apply to outstation trips only' }, 400)
    const t = (r.tolls || []).find((x: any) => String(x._id) === tollId)
    if (!t) return withCors({ error: 'Toll not found' }, 404)
    if (t.reportedAt) return body(r, { alreadyReported: true })
    return withCors({ error: 'This trip can no longer be reported' }, 409)
  }

  const toll = ride.tolls.find((t: any) => String(t._id) === tollId)
  const when = toll?.at ? new Date(toll.at).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }) : ''
  try {
    const ticket: any = await SupportTicket.create({
      userId: riderId,
      role: 'user',
      userName: ride.riderName || 'Rider',
      subject: `Toll complaint · ₹${toll?.amount ?? ''}${toll?.place ? ` · ${toll.place}` : ''}`,
      category: 'toll',
      rideId: ride._id,
      priority: 'medium',
      messages: [{
        sender: 'user',
        message: [
          `Reason: ${REASONS[reason]}`,
          note ? `Rider's note: ${note}` : '',
          `Toll: ₹${toll?.amount ?? ''}${toll?.place ? ` at ${toll.place}` : ''}${when ? `, ${when}` : ''}`,
          `Entered by driver ${ride.driverName || ''} (${toll?.source === 'prompt' ? 'from the toll-road prompt' : 'added by hand'})`,
          `Ride ${String(ride._id)} · all tolls on the trip: ₹${ride.tollCharge || 0}`,
        ].filter(Boolean).join('\n'),
      }],
    })
    const updated = await Ride.findOneAndUpdate(
      { _id: rideId, 'tolls._id': tollId },
      { $set: { 'tolls.$.ticketId': ticket._id } },
      { returnDocument: 'after' },
    ).lean()
    return body(updated || ride, { ticketId: String(ticket._id) })
  } catch (e: any) {
    await Ride.updateOne(
      // $elemMatch, so the positional $ below is this toll, unambiguously.
      { _id: rideId, tolls: { $elemMatch: { _id: tollId, reportedAt } } },
      { $unset: { 'tolls.$.reportedAt': '', 'tolls.$.reportReason': '', 'tolls.$.reportNote': '' } },
    )
    return withCors({ error: 'Could not send the report. Please try again.' }, 500)
  }
}

/**
 * Why an update matched nothing, as a response. A retried add whose entry
 * already landed, and a remove of an entry already gone, are successes: the
 * list is already in the state the driver asked for.
 */
async function explain(rideId: string, driverId: string, clientRef: string | null, tollId?: string) {
  const ride: any = await Ride.findById(rideId)
    .select('driverId service status awaitingPayment tolls tollCharge').lean()
  if (!ride) return withCors({ error: 'Ride not found' }, 404)
  if (!ride.driverId || String(ride.driverId) !== String(driverId)) {
    return withCors({ error: 'Not your ride' }, 403)
  }
  if (ride.service !== 'outstation') return withCors({ error: 'Tolls apply to outstation trips only' }, 400)
  if (ride.status !== 'ongoing' || ride.awaitingPayment) {
    return withCors({ error: 'Tolls can only be changed while the trip is in progress' }, 409)
  }
  const tolls: any[] = ride.tolls || []
  if (clientRef && tolls.some(t => t.clientRef === clientRef)) return body(ride, { duplicate: true })
  if (tollId !== undefined && !tolls.some(t => String(t._id) === tollId)) return body(ride, { alreadyRemoved: true })
  if (clientRef && tolls.length >= MAX_TOLL_ENTRIES) {
    return withCors({ error: `A trip can have at most ${MAX_TOLL_ENTRIES} tolls` }, 409)
  }
  // The trip changed between the update and this read (it just ended). Report
  // it as the state the driver will see on retry.
  return withCors({ error: 'Tolls can only be changed while the trip is in progress' }, 409)
}
