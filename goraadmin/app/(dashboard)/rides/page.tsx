'use client'
import { useState, useEffect, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { PageHeader } from '@/components/ui/page-header'
import { RidesPager } from '@/components/rides/pager'
import { fmtISTShort, rideHref } from '@/components/rides/format'
import { Car, CheckCircle, XCircle, Clock, Search, Download } from 'lucide-react'

const LIMIT = 50

export default function RidesPage() {
  const router = useRouter()
  const [rides, setRides] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [applied, setApplied] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [serviceFilter, setServiceFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  const filterParams = useCallback(() => {
    const p = new URLSearchParams()
    if (statusFilter !== 'all') p.set('status', statusFilter)
    if (serviceFilter !== 'all') p.set('service', serviceFilter)
    if (applied) p.set('search', applied)
    if (dateFrom) p.set('dateFrom', dateFrom)
    if (dateTo) p.set('dateTo', dateTo)
    return p
  }, [statusFilter, serviceFilter, applied, dateFrom, dateTo])

  // /rides?search=<ride id or name> (links from other pages). Read from
  // window.location so the page needs no Suspense boundary.
  const [ready, setReady] = useState(false)
  useEffect(() => {
    const q = new URLSearchParams(window.location.search).get('search')
    if (q) { const v = q.trim().slice(0, 100); setSearch(v); setApplied(v) }
    setReady(true)
  }, [])

  useEffect(() => {
    if (!ready) return
    setLoading(true); setError('')
    const p = filterParams()
    p.set('page', String(page)); p.set('limit', String(LIMIT)); p.set('stats', '1')
    fetch(`/api/rides?${p}`)
      .then(async r => { const d = await r.json().catch(() => ({})); if (!r.ok) throw new Error(d?.error || `Failed (${r.status})`); return d })
      .then(d => { setRides(d.rides || []); setTotal(d.total || 0); setStats(d.stats || null) })
      .catch(e => { setError(e.message); setRides([]); setTotal(0) })
      .finally(() => setLoading(false))
  }, [ready, page, filterParams])

  // Any filter change goes back to page 1.
  const setF = (fn: (v: any) => void) => (v: any) => { fn(v); setPage(1) }
  const csvHref = `/api/rides?${(() => { const p = filterParams(); p.set('format', 'csv'); return p })()}`
  const by = stats?.byStatus || {}
  const dateBad = !!(dateFrom && dateTo && dateFrom > dateTo)

  return (
    <div>
      <Header title="All Rides" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="All Rides"
          subtitle="View and manage all ride bookings"
          action={
            <a href={csvHref} download
              title="Downloads every ride matching the filters (newest first, up to 20,000)"
              className="flex items-center gap-2 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm font-medium hover:bg-gray-200">
              <Download className="w-4 h-4" /> Export CSV
            </a>
          }
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={Car} label="Total Rides" value={stats ? stats.total : '…'} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={CheckCircle} label="Completed" value={stats ? by.completed || 0 : '…'} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={XCircle} label="Cancelled" value={stats ? by.cancelled || 0 : '…'} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={Clock} label="Ongoing" value={stats ? by.ongoing || 0 : '…'} iconColor="text-blue-600" iconBg="bg-blue-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3 items-center">
            <form className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48"
              onSubmit={e => { e.preventDefault(); setApplied(search.trim()); setPage(1) }}>
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)} onBlur={() => { if (search.trim() !== applied) { setApplied(search.trim()); setPage(1) } }}
                placeholder="Name, phone, city or ride id — Enter to search" aria-label="Search rides" className="bg-transparent text-sm outline-none w-full" />
            </form>
            <select aria-label="Filter by status" value={statusFilter} onChange={e => setF(setStatusFilter)(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="accepted">Accepted</option>
              <option value="arrived">Arrived</option>
              <option value="ongoing">Ongoing</option>
              <option value="completed">Completed</option>
              <option value="cancelled">Cancelled</option>
            </select>
            <select aria-label="Filter by service" value={serviceFilter} onChange={e => setF(setServiceFilter)(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Services</option>
              <option value="taxi">Taxi</option>
              <option value="rental">Rental</option>
              <option value="outstation">Outstation</option>
              <option value="delivery">Delivery</option>
              <option value="hire_driver">Hire a driver</option>
            </select>
            <label className="flex items-center gap-1 text-xs text-gray-500">From
              <input type="date" aria-label="From date (IST)" value={dateFrom} onChange={e => setF(setDateFrom)(e.target.value)}
                className="border border-gray-200 rounded-lg px-2 py-1.5 text-sm bg-white" />
            </label>
            <label className="flex items-center gap-1 text-xs text-gray-500">To
              <input type="date" aria-label="To date (IST)" value={dateTo} onChange={e => setF(setDateTo)(e.target.value)}
                className={`border rounded-lg px-2 py-1.5 text-sm bg-white ${dateBad ? 'border-red-400' : 'border-gray-200'}`} />
            </label>
            {(dateFrom || dateTo || applied || statusFilter !== 'all' || serviceFilter !== 'all') && (
              <button type="button" className="text-xs text-blue-600 hover:underline" onClick={() => {
                setDateFrom(''); setDateTo(''); setSearch(''); setApplied(''); setStatusFilter('all'); setServiceFilter('all'); setPage(1)
              }}>Clear filters</button>
            )}
          </div>
          {error && <p className="px-4 py-3 text-sm text-red-600 border-b border-red-100 bg-red-50">{error}</p>}

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Ride', 'Rider', 'Driver', 'Pickup → Drop', 'Service', 'Fare', 'Payment', 'Status', 'Date (IST)'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {rides.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50 cursor-pointer" onClick={() => router.push(rideHref(r._id))}>
                      <td className="px-4 py-3"><Link href={rideHref(r._id)} onClick={e => e.stopPropagation()} className="text-blue-600 hover:underline font-mono text-xs">{String(r._id).slice(-8)}</Link>
                        {r.needsReview && <span className="ml-1 text-[10px] font-bold text-red-600">REVIEW</span>}</td>
                      <td className="px-4 py-3 text-gray-800">{r.riderName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap max-w-[360px] truncate">
                        {r.pickupAddress}
                        {Array.isArray(r.stops) && r.stops.length > 0 && <span className="text-orange-600"> → +{r.stops.length} stop{r.stops.length > 1 ? 's' : ''}</span>}
                        {' → '}{r.dropAddress}
                        {r.waitingChargeTotal > 0 && <span className="text-purple-600"> · wait ₹{r.waitingChargeTotal}</span>}
                      </td>
                      <td className="px-4 py-3 text-gray-600 capitalize">{String(r.service || 'taxi').replace('_', ' ')}</td>
                      <td className="px-4 py-3 font-semibold text-gray-800">₹{r.totalFare ?? r.fare ?? 0}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs capitalize">{r.paymentMode}{r.paymentStatus === 'pending' && r.status === 'completed' ? ' · unpaid' : ''}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                      <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">{fmtISTShort(r.createdAt)}</td>
                    </tr>
                  ))}
                  {rides.length === 0 && (
                    <tr><td colSpan={9} className="text-center text-gray-400 py-12">No rides found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
          <RidesPager page={page} limit={LIMIT} total={total} onPage={setPage} loading={loading} />
        </div>
      </div>
    </div>
  )
}
