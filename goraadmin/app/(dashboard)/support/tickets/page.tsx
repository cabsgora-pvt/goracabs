'use client'
import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Pager } from '@/components/ui/pager'
import { refreshAlerts } from '@/components/admin-alerts'
import { MessageSquare, Clock, CheckCircle, Eye, Send, XCircle } from 'lucide-react'

const STATUS_OPTS = [
  { v: 'open', label: 'Open' }, { v: 'in_progress', label: 'In progress' },
  { v: 'resolved', label: 'Resolved' }, { v: 'closed', label: 'Closed' },
]
const LIMIT = 50
const fmt = (d?: string) => d ? new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' }) : '—'

function Linked({ t }: { t: any }) {
  return (
    <div className="flex flex-col gap-0.5 text-xs">
      {t.userId && <Link href={`/users/${t.userId}`} className="text-blue-600 hover:underline">Rider: {t.user?.name || t.user?.phone || 'open'}</Link>}
      {t.driverId && <Link href={`/drivers/${t.driverId}`} className="text-blue-600 hover:underline">Driver: {t.driver?.name || t.driver?.phone || t.driverPhone || 'open'}</Link>}
      {t.rideId && <Link href={`/rides/${t.rideId}`} className="text-blue-600 hover:underline">Ride …{String(t.rideId).slice(-6)}{t.ride?.status ? ` · ${t.ride.status}` : ''}</Link>}
      {!t.userId && !t.driverId && !t.rideId && <span className="text-gray-400">—</span>}
    </div>
  )
}

export default function TicketsPage() {
  const [tickets, setTickets] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [page, setPage] = useState(1)
  const [f, setF] = useState({ status: 'unresolved', priority: '', role: '', q: '', sort: 'oldest_open' })
  const [loading, setLoading] = useState(true)
  const [viewTicket, setViewTicket] = useState<any>(null)
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchTickets = useCallback(() => {
    setLoading(true)
    const p = new URLSearchParams({ page: String(page), limit: String(LIMIT) })
    for (const [k, v] of Object.entries(f)) if (v) p.set(k, v)
    fetch(`/api/support/tickets?${p}`)
      .then(r => r.json())
      .then(d => { setTickets(d.tickets || []); setTotal(d.total || 0); setCounts(d.counts || {}); setLoading(false) })
      .catch(() => setLoading(false))
  }, [page, f])
  useEffect(() => { fetchTickets() }, [fetchTickets])
  const set = (k: string, v: string) => { setPage(1); setF({ ...f, [k]: v }) }

  const save = async (body: { message?: string; status?: string }) => {
    if (!viewTicket) return
    setSending(true)
    const res = await fetch(`/api/support/tickets/${viewTicket._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    setSending(false)
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { setToast({ msg: d.error || 'Could not update the ticket', type: 'error' }); return }
    // Keep the linked names the list already has.
    const merged = { ...viewTicket, ...d }
    setTickets(prev => prev.map(t => t._id === viewTicket._id ? merged : t))
    setViewTicket(merged)
    if (body.message) setReply('')
    setToast({ msg: body.message ? 'Reply sent' : `Status set to ${String(body.status).replace('_', ' ')}`, type: 'success' })
    fetchTickets(); refreshAlerts()
  }

  const inp = 'border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white'

  return (
    <div>
      <Header title="Support Tickets" />
      <div className="p-6 space-y-6">
        <PageHeader title="Support Tickets" subtitle="Handle customer and driver support requests" />

        <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
          <StatsCard icon={MessageSquare} label="Open" value={counts.open || 0} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={Clock} label="In Progress" value={counts.in_progress || 0} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={CheckCircle} label="Resolved" value={counts.resolved || 0} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={XCircle} label="Closed" value={counts.closed || 0} iconColor="text-gray-600" iconBg="bg-gray-50" />
        </div>

        <div className="bg-white rounded-xl border p-4 flex flex-wrap gap-3 items-end">
          <div>
            <label className="block text-xs text-gray-500 mb-1">Status</label>
            <select className={inp} value={f.status} onChange={e => set('status', e.target.value)} aria-label="Status">
              <option value="unresolved">Open + in progress</option>
              {STATUS_OPTS.map(o => <option key={o.v} value={o.v}>{o.label}</option>)}
              <option value="all">All</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Priority</label>
            <select className={inp} value={f.priority} onChange={e => set('priority', e.target.value)} aria-label="Priority">
              <option value="">Any</option><option value="high">High</option><option value="medium">Medium</option><option value="low">Low</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">From</label>
            <select className={inp} value={f.role} onChange={e => set('role', e.target.value)} aria-label="Raised by">
              <option value="">Riders and drivers</option><option value="user">Riders</option><option value="driver">Drivers</option>
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Sort</label>
            <select className={inp} value={f.sort} onChange={e => set('sort', e.target.value)} aria-label="Sort">
              <option value="oldest_open">Oldest open first (queue)</option>
              <option value="newest">Newest first</option>
              <option value="oldest">Oldest first</option>
            </select>
          </div>
          <div className="flex-1 min-w-48">
            <label className="block text-xs text-gray-500 mb-1">Search</label>
            <input className={`${inp} w-full`} value={f.q} onChange={e => set('q', e.target.value)} placeholder="Subject, name or phone" aria-label="Search" />
          </div>
        </div>

        {loading && tickets.length === 0 ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  {['Raised by', 'Subject', 'Linked', 'Priority', 'Status', 'Created', 'Actions'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {tickets.map(t => (
                  <tr key={t._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <p className="font-medium text-gray-800">{t.userName || '—'}</p>
                      <p className="text-xs text-gray-500 capitalize">{t.role === 'driver' ? 'driver' : 'rider'}{t.zoneName ? ` · ${t.zoneName}` : ''}</p>
                    </td>
                    <td className="px-4 py-3 text-gray-700">
                      {t.subject}
                      {t.category && <p className="text-xs text-gray-400">{t.category}</p>}
                    </td>
                    <td className="px-4 py-3"><Linked t={t} /></td>
                    <td className="px-4 py-3"><Badge status={t.priority} /></td>
                    <td className="px-4 py-3"><Badge status={t.status} /></td>
                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">{fmt(t.createdAt)}</td>
                    <td className="px-4 py-3">
                      <button type="button" onClick={() => { setViewTicket(t); setReply('') }}
                        className="flex items-center gap-1 px-3 py-1 bg-blue-50 text-blue-600 rounded-lg text-xs hover:bg-blue-100">
                        <Eye className="w-3.5 h-3.5" /> View
                      </button>
                    </td>
                  </tr>
                ))}
                {tickets.length === 0 && (
                  <tr><td colSpan={7} className="text-center text-gray-400 py-12">No tickets match</td></tr>
                )}
              </tbody>
            </table>
            <div className="px-4 border-t border-gray-100">
              <Pager page={page} limit={LIMIT} total={total} onPage={setPage} noun={['ticket', 'tickets']} />
            </div>
          </div>
        )}
      </div>

      {viewTicket && (
        <Modal title={`${viewTicket.subject || 'Ticket'}`} onClose={() => setViewTicket(null)} size="lg">
          <div className="space-y-4">
            <div className="flex gap-3 flex-wrap items-center">
              <Badge status={viewTicket.status} />
              <Badge status={viewTicket.priority} />
              {viewTicket.category && (
                <span className="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">{viewTicket.category}</span>
              )}
              <span className="text-xs text-gray-500">Created {fmt(viewTicket.createdAt)}</span>
            </div>
            <Linked t={viewTicket} />
            <div className="space-y-3 max-h-60 overflow-y-auto">
              {(viewTicket.messages || []).map((msg: any, i: number) => (
                <div key={msg._id || i} className={`flex ${msg.sender === 'admin' ? 'justify-end' : 'justify-start'}`}>
                  <div className={`max-w-xs rounded-xl p-3 ${msg.sender === 'admin' ? 'bg-blue-50 text-blue-900' : 'bg-gray-100 text-gray-800'}`}>
                    <p className="text-xs font-semibold mb-1 capitalize">{msg.sender}</p>
                    <p className="text-sm whitespace-pre-wrap break-words">{msg.message}</p>
                    <p className="text-xs text-gray-400 mt-1">{msg.sentAt ? fmt(msg.sentAt) : ''}</p>
                  </div>
                </div>
              ))}
              {(!viewTicket.messages || viewTicket.messages.length === 0) && (
                <p className="text-gray-400 text-sm text-center py-4">No messages yet</p>
              )}
            </div>
            <div className="flex gap-3 pt-2 border-t border-gray-100">
              <input
                value={reply}
                onChange={e => setReply(e.target.value)}
                maxLength={2000}
                placeholder="Type your reply..."
                aria-label="Reply"
                className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                onKeyDown={e => { if (e.key === 'Enter' && reply.trim() && !sending) save({ message: reply }) }}
              />
              <button type="button" onClick={() => save({ message: reply })} disabled={sending || !reply.trim()}
                className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
                <Send className="w-4 h-4" /> Reply
              </button>
            </div>
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className="text-gray-500">Set status:</span>
              {STATUS_OPTS.map(o => (
                <button key={o.v} type="button" disabled={sending || viewTicket.status === o.v} onClick={() => save({ status: o.v })}
                  className={`px-3 py-1 rounded-lg border text-xs font-medium disabled:opacity-50 ${viewTicket.status === o.v ? 'bg-gray-100 border-gray-300' : 'hover:bg-gray-50 border-gray-200'}`}>
                  {o.label}
                </button>
              ))}
            </div>
            <p className="text-xs text-gray-400">A reply does not close the ticket. Replying to an open ticket marks it in progress.</p>
          </div>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
