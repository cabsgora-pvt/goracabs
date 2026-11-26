'use client'
import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { RidesPager } from '@/components/rides/pager'
import { SearchBox } from '@/components/rides/search-box'
import { fmtISTShort, rideHref } from '@/components/rides/format'
import { XCircle } from 'lucide-react'

const LIMIT = 50

export default function CancelledRidesPage() {
  const router = useRouter()
  const [rides, setRides] = useState<any[]>([])
  const [cancellationReasons, setCancellationReasons] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState<any>(null)
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')

  useEffect(() => {
    const p = new URLSearchParams({ page: String(page), limit: String(LIMIT) })
    if (search) p.set('search', search)
    if (dateFrom) p.set('dateFrom', dateFrom)
    if (dateTo) p.set('dateTo', dateTo)
    setLoading(true); setError('')
    fetch(`/api/rides/cancelled?${p}`)
      .then(async r => { const d = await r.json().catch(() => ({})); if (!r.ok) throw new Error(d?.error || `Failed (${r.status})`); return d })
      .then(d => { setRides(d.rides || []); setCancellationReasons(d.cancellationReasons || []); setTotal(d.total || 0); setStats(d.stats || null) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [page, search, dateFrom, dateTo])

  const by = stats?.byCancelledBy || {}
  const byRider = by.rider || 0
  const byDriver = by.driver || 0
  const byAdmin = by.admin || 0
  const bySystem = (by.system || 0) + (by.System || 0)

  const maxCount = cancellationReasons[0]?.count || 1

  return (
    <div>
      <Header title="Cancelled Rides" />
      <div className="p-6 space-y-6">
        <PageHeader title="Cancelled Rides" subtitle="View and analyze ride cancellations" />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={XCircle} label="Total Cancelled" value={stats ? total : "…"} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={XCircle} label="By Rider" value={byRider} iconColor="text-orange-600" iconBg="bg-orange-50" />
          <StatsCard icon={XCircle} label="By Driver" value={byDriver} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={XCircle} label="Auto / Admin" value={`${bySystem} / ${byAdmin}`} iconColor="text-gray-600" iconBg="bg-gray-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3 items-center">
            <SearchBox value={search} onSearch={v => { setSearch(v); setPage(1) }} placeholder="Search rider, driver, phone, reason" className="max-w-md" />
            <label className="flex items-center gap-1 text-xs text-gray-500">From
              <input type="date" aria-label="From date (IST)" value={dateFrom} onChange={e => { setDateFrom(e.target.value); setPage(1) }} className="border border-gray-200 rounded-lg px-2 py-1.5 text-sm bg-white" />
            </label>
            <label className="flex items-center gap-1 text-xs text-gray-500">To
              <input type="date" aria-label="To date (IST)" value={dateTo} onChange={e => { setDateTo(e.target.value); setPage(1) }} className="border border-gray-200 rounded-lg px-2 py-1.5 text-sm bg-white" />
            </label>
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
                    {['Ride', 'Rider', 'Driver', 'Route', 'Reason', 'Cancelled By', 'Date (IST)'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {rides.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50 cursor-pointer" onClick={() => router.push(rideHref(r._id))}>
                      <td className="px-4 py-3"><Link href={rideHref(r._id)} onClick={e => e.stopPropagation()} className="text-blue-600 hover:underline font-mono text-xs">{String(r._id).slice(-8)}</Link></td>
                      <td className="px-4 py-3 text-gray-800">{r.riderName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs">{r.pickupAddress} → {r.dropAddress}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs">{r.cancellationReason || '—'}</td>
                      <td className="px-4 py-3">
                        <span className={`text-xs px-2 py-0.5 rounded-full ${
                          r.cancelledBy === 'rider' ? 'bg-orange-100 text-orange-700' :
                          r.cancelledBy === 'driver' ? 'bg-yellow-100 text-yellow-700' :
                          'bg-gray-100 text-gray-600'
                        }`}>
                          {r.cancelledBy || 'System'}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-gray-500 text-xs">{fmtISTShort(r.createdAt)}</td>
                    </tr>
                  ))}
                  {rides.length === 0 && (
                    <tr><td colSpan={7} className="text-center text-gray-400 py-12">No cancelled rides</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
          <RidesPager page={page} limit={LIMIT} total={total} onPage={setPage} loading={loading} />
        </div>

        {cancellationReasons.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
            <h3 className="font-semibold text-gray-800 mb-4">Top Cancellation Reasons</h3>
            <div className="space-y-3">
              {cancellationReasons.map(r => (
                <div key={r.reason} className="flex items-center gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex justify-between text-sm mb-1">
                      <span className="text-gray-700 truncate">{r.reason}</span>
                      <span className="text-gray-500 ml-2 flex-shrink-0">{r.count} rides</span>
                    </div>
                    <div className="h-2 bg-gray-100 rounded-full">
                      <div className="h-2 bg-red-400 rounded-full" style={{ width: `${(r.count / maxCount) * 100}%` }} />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
