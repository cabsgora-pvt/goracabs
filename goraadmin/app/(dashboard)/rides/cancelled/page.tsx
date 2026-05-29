'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { Search, XCircle } from 'lucide-react'

export default function CancelledRidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [cancellationReasons, setCancellationReasons] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')

  useEffect(() => {
    fetch('/api/rides/cancelled')
      .then(r => r.json())
      .then(d => { setRides(d.rides || []); setCancellationReasons(d.cancellationReasons || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const filtered = rides.filter(r => {
    if (!search) return true
    const s = search.toLowerCase()
    return r.riderName?.toLowerCase().includes(s) || r.driverName?.toLowerCase().includes(s)
  })

  const byRider = rides.filter(r => r.cancelledBy === 'rider').length
  const byDriver = rides.filter(r => r.cancelledBy === 'driver').length
  const bySystem = rides.filter(r => !r.cancelledBy || r.cancelledBy === 'system').length
  const maxCount = cancellationReasons[0]?.count || 1

  return (
    <div>
      <Header title="Cancelled Rides" />
      <div className="p-6 space-y-6">
        <PageHeader title="Cancelled Rides" subtitle="View and analyze ride cancellations" />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={XCircle} label="Total Cancelled" value={rides.length} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={XCircle} label="By Rider" value={byRider} iconColor="text-orange-600" iconBg="bg-orange-50" />
          <StatsCard icon={XCircle} label="By Driver" value={byDriver} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={XCircle} label="Auto-Cancelled" value={bySystem} iconColor="text-gray-600" iconBg="bg-gray-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 max-w-sm">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search cancellations..." className="bg-transparent text-sm outline-none w-full" />
            </div>
          </div>

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Rider', 'Driver', 'Route', 'Reason', 'Cancelled By', 'Date'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
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
                      <td className="px-4 py-3 text-gray-500 text-xs">{r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'}</td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={6} className="text-center text-gray-400 py-12">No cancelled rides</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
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
