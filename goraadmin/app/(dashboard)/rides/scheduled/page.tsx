'use client'
import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { RidesPager } from '@/components/rides/pager'
import { SearchBox } from '@/components/rides/search-box'
import { RideActions } from '@/components/rides/ride-actions'
import { fmtIST, rideHref } from '@/components/rides/format'

const LIMIT = 50
const SOON_MS = 30 * 60_000
const TWO_H_MS = 2 * 3600_000

/** 'red' — no driver and due within 30 min (or overdue); 'amber' — within 2 h. */
function urgencyOf(r: any, now: number): 'red' | 'amber' | null {
  if (r.status !== 'pending' || r.driverId || !r.scheduledAt) return null
  const left = new Date(r.scheduledAt).getTime() - now
  if (left <= SOON_MS) return 'red'
  if (left <= TWO_H_MS) return 'amber'
  return null
}

function dueIn(at: any, now: number) {
  const ms = new Date(at).getTime() - now
  const m = Math.round(Math.abs(ms) / 60000)
  const s = m >= 120 ? `${Math.floor(m / 60)} h ${m % 60} m` : `${m} min`
  return ms >= 0 ? `in ${s}` : `${s} overdue`
}

export default function ScheduledRidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [dateFilter, setDateFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [now, setNow] = useState(Date.now())
  const [toast, setToast] = useState<string | null>(null)

  const load = useCallback((quiet = false) => {
    const p = new URLSearchParams({ page: String(page), limit: String(LIMIT), status: statusFilter })
    if (search) p.set('search', search)
    if (dateFilter) p.set('date', dateFilter)
    if (!quiet) setLoading(true)
    fetch(`/api/rides/scheduled?${p}`)
      .then(async r => { const d = await r.json().catch(() => ({})); if (!r.ok) throw new Error(d?.error || `Failed (${r.status})`); return d })
      .then(d => { setRides(d.rides || []); setTotal(d.total || 0); setStats(d.stats || null); setError(''); setNow(Date.now()) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [page, statusFilter, search, dateFilter])
  useEffect(() => { load() }, [load])
  // Keep the due-time colours current, and pick up rides that were taken.
  useEffect(() => { const t = setInterval(() => load(true), 30_000); return () => clearInterval(t) }, [load])

  return (
    <div>
      <Header title="Scheduled Rides" />
      <div className="p-6 space-y-6">
        <PageHeader title="Scheduled Rides" subtitle={`${total} upcoming scheduled ride${total === 1 ? '' : 's'} · times in IST`} />

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4"><div className="text-xs text-gray-500">No driver yet</div><div className="text-xl font-bold text-gray-900">{stats?.unassigned ?? '…'}</div></div>
          <div className="bg-white rounded-xl border border-red-200 shadow-sm p-4"><div className="text-xs text-red-600">No driver · due within 30 min or overdue</div><div className="text-xl font-bold text-red-700">{stats?.dueSoon ?? '…'}</div></div>
          <div className="bg-white rounded-xl border border-amber-200 shadow-sm p-4"><div className="text-xs text-amber-700">No driver · due in 30 min – 2 h</div><div className="text-xl font-bold text-amber-700">{stats?.dueIn2h ?? '…'}</div></div>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <SearchBox value={search} onSearch={v => { setSearch(v); setPage(1) }} placeholder="Search rider, driver, phone, address" />
            <select aria-label="Filter by assignment" value={statusFilter} onChange={e => { setStatusFilter(e.target.value); setPage(1) }}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white">
              <option value="all">All upcoming</option>
              <option value="pending">No driver yet</option>
              <option value="accepted">Driver assigned</option>
            </select>
            <input aria-label="Filter by date (IST)" type="date" value={dateFilter} onChange={e => { setDateFilter(e.target.value); setPage(1) }}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          {error && <p className="px-4 py-3 text-sm text-red-600 bg-red-50">{error}</p>}

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Ride', 'Rider', 'Driver', 'Pickup', 'Drop', 'Due (IST)', 'Service', 'Fare', 'Status', ''].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {rides.map(r => {
                    const u = urgencyOf(r, now)
                    return (
                      <tr key={r._id} data-urgency={u || ''} className={u === 'red' ? 'bg-red-50 hover:bg-red-100' : u === 'amber' ? 'bg-amber-50 hover:bg-amber-100' : 'hover:bg-gray-50'}>
                        <td className="px-4 py-3"><Link href={rideHref(r._id)} className="text-blue-600 hover:underline font-mono text-xs">{String(r._id).slice(-8)}</Link></td>
                        <td className="px-4 py-3 text-gray-800">{r.riderName || '—'}<div className="text-xs text-gray-500">{r.riderPhone}</div></td>
                        <td className="px-4 py-3 text-gray-600">{r.driverName || <span className={u ? 'font-semibold text-red-600' : 'text-gray-400'}>No driver yet</span>}</td>
                        <td className="px-4 py-3 text-gray-600 text-xs">{r.pickupAddress}</td>
                        <td className="px-4 py-3 text-gray-600 text-xs">{r.dropAddress}</td>
                        <td className="px-4 py-3 whitespace-nowrap">
                          <div className="text-gray-800">{fmtIST(r.scheduledAt)}</div>
                          {r.scheduledAt && <div className={`text-xs ${u === 'red' ? 'text-red-700 font-semibold' : u === 'amber' ? 'text-amber-700 font-semibold' : 'text-gray-500'}`}>{dueIn(r.scheduledAt, now)}</div>}
                        </td>
                        <td className="px-4 py-3 text-gray-600 capitalize">{String(r.service || 'taxi').replace('_', ' ')}</td>
                        <td className="px-4 py-3 font-semibold text-gray-800">₹{r.fare ?? 0}{r.prepaidAmount > 0 && <div className="text-xs font-normal text-gray-500">prepaid ₹{r.prepaidAmount}</div>}</td>
                        <td className="px-4 py-3"><Badge status={r.status} /></td>
                        <td className="px-4 py-3"><RideActions ride={r} only={['cancel']} size="sm" onDone={m => { setToast(m); load(true) }} /></td>
                      </tr>
                    )
                  })}
                  {rides.length === 0 && (
                    <tr><td colSpan={10} className="text-center text-gray-400 py-12">No scheduled rides found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
          <RidesPager page={page} limit={LIMIT} total={total} onPage={setPage} loading={loading} />
        </div>
      </div>
      {toast && <Toast message={toast} type="success" onClose={() => setToast(null)} />}
    </div>
  )
}
