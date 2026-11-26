export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { guardAdmin } from '@/lib/admin-guard'
import SOSAlert, { SOS_OPEN_STATUSES } from '@/models/SOSAlert'
import SupportTicket from '@/models/SupportTicket'
import Driver from '@/models/Driver'
import Withdrawal from '@/models/Withdrawal'
import AccountRequest from '@/models/AccountRequest'
import Ride from '@/models/Ride'

// GET — what needs an admin now, for the topbar bell, the SOS banner and the
// sidebar badges (one poll, every 10 s while the tab is visible). Counts plus
// the latest few items, each with the page that handles it. Read-only and
// cheap: indexed counts and a handful of small finds.
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const [sosActive, sosAcknowledged, ticketsOpen, driversPending, withdrawalsPending, accountRequests, needsReview,
      sos, tickets, drivers, withdrawals, requests] = await Promise.all([
      SOSAlert.countDocuments({ status: 'active' }),
      SOSAlert.countDocuments({ status: 'acknowledged' }),
      SupportTicket.countDocuments({ status: { $in: ['open', 'in_progress'] } }),
      Driver.countDocuments({ status: 'pending' }),
      Withdrawal.countDocuments({ status: 'pending' }),
      AccountRequest.countDocuments({ status: 'pending' }),
      Ride.countDocuments({ needsReview: true }),
      SOSAlert.find({ status: { $in: SOS_OPEN_STATUSES } }).sort({ createdAt: -1 }).limit(5).select('name phone triggeredBy status createdAt').lean(),
      SupportTicket.find({ status: 'open' }).sort({ createdAt: -1 }).limit(3).select('subject userName priority createdAt').lean(),
      Driver.find({ status: 'pending' }).sort({ createdAt: 1 }).limit(3).select('name phone createdAt').lean(),
      Withdrawal.find({ status: 'pending' }).sort({ createdAt: 1 }).limit(3).select('driverName amount createdAt').lean(),
      AccountRequest.find({ status: 'pending' }).sort({ createdAt: 1 }).limit(3).select('name kind createdAt').lean(),
    ])
    const items = [
      ...sos.map((s: any) => ({ kind: 'sos', id: String(s._id), at: s.createdAt, href: '/support/sos',
        text: `SOS${s.status === 'acknowledged' ? ' (acknowledged)' : ''}: ${s.triggeredBy === 'driver' ? 'driver' : 'rider'} ${s.name || s.phone || ''}` })),
      ...tickets.map((t: any) => ({ kind: 'ticket', id: String(t._id), at: t.createdAt, href: '/support/tickets',
        text: `Ticket: ${String(t.subject || 'No subject').slice(0, 60)}${t.userName ? ' — ' + t.userName : ''}` })),
      ...drivers.map((d: any) => ({ kind: 'driver', id: String(d._id), at: d.createdAt, href: `/drivers/${d._id}`,
        text: `Driver waiting for approval: ${d.name || d.phone || ''}` })),
      ...withdrawals.map((w: any) => ({ kind: 'withdrawal', id: String(w._id), at: w.createdAt, href: '/finance/withdrawals',
        text: `Withdrawal ₹${Math.round(w.amount || 0).toLocaleString('en-IN')} — ${w.driverName || 'driver'}` })),
      ...requests.map((r: any) => ({ kind: 'request', id: String(r._id), at: r.createdAt, href: '/account-requests',
        text: `${r.kind === 'delete' ? 'Account deletion' : 'Zone change'} request — ${r.name || ''}` })),
    ]
    return NextResponse.json({
      counts: { sosActive, sosAcknowledged, ticketsOpen, driversPending, withdrawalsPending, accountRequests, needsReview },
      items,
      at: new Date(),
    }, { headers: { 'Cache-Control': 'no-store' } })
  } catch (error: any) {
    return NextResponse.json({ error: error.message || 'Server error' }, { status: 500 })
  }
}
