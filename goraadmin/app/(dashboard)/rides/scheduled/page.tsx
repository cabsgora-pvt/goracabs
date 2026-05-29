'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Badge } from '@/components/ui/badge'
import { Search } from 'lucide-react'

export default function ScheduledRidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [dateFilter, setDateFilter] = useState('')

  useEffect(() => {
    fetch('/api/rides/scheduled')
      .then(r => r.json())
      .then(d => { setRides(d.rides || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const filtered = rides.filter(r => {
    const matchSearch = !search ||
      r.riderName?.toLowerCase().includes(search.toLowerCase()) ||
      r.driverName?.toLowerCase().includes(search.toLowerCase())
    const matchDate = !dateFilter || (r.scheduledAt && r.scheduledAt.startsWith(dateFilter))
    return matchSearch && matchDate
  })

  return (
    <div>
      <Header title="Scheduled Rides" />
      <div className="p-6 space-y-6">
        <PageHeader title="Scheduled Rides" subtitle={`${rides.length} rides scheduled`} />

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search rides..." className="bg-transparent text-sm outline-none w-full" />
            </div>
            <input aria-label="Filter by date" type="date" value={dateFilter} onChange={e => setDateFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
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
                    {['Rider', 'Driver', 'Pickup', 'Drop', 'Scheduled Time', 'Service', 'Fare', 'Status'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 text-gray-800">{r.riderName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs">{r.pickupAddress}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs">{r.dropAddress}</td>
                      <td className="px-4 py-3 text-gray-700">{r.scheduledAt ? new Date(r.scheduledAt).toLocaleString() : '—'}</td>
                      <td className="px-4 py-3 text-gray-600 capitalize">{r.service}</td>
                      <td className="px-4 py-3 font-semibold text-gray-800">₹{r.fare}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={8} className="text-center text-gray-400 py-12">No scheduled rides found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
