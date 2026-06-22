'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Car, CheckCircle, XCircle, Clock, Search, Download } from 'lucide-react'

export default function RidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [serviceFilter, setServiceFilter] = useState('all')
  const [toast, setToast] = useState<{ msg: string } | null>(null)

  const fetchRides = () => {
    setLoading(true)
    const params = new URLSearchParams({ limit: '100' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    if (serviceFilter !== 'all') params.set('service', serviceFilter)
    if (search) params.set('search', search)
    fetch(`/api/rides?${params}`)
      .then(r => r.json())
      .then(d => { setRides(d.rides || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchRides() }, [statusFilter, serviceFilter])

  const filtered = rides.filter(r => {
    if (!search) return true
    const s = search.toLowerCase()
    return r.riderName?.toLowerCase().includes(s) || r.driverName?.toLowerCase().includes(s)
  })

  return (
    <div>
      <Header title="All Rides" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="All Rides"
          subtitle="View and manage all ride bookings"
          action={
            <button type="button" onClick={() => setToast({ msg: 'CSV export started...' })}
              className="flex items-center gap-2 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg text-sm font-medium hover:bg-gray-200">
              <Download className="w-4 h-4" /> Export CSV
            </button>
          }
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={Car} label="Total Rides" value={rides.length} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={CheckCircle} label="Completed" value={rides.filter(r => r.status === 'completed').length} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={XCircle} label="Cancelled" value={rides.filter(r => r.status === 'cancelled').length} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={Clock} label="Ongoing" value={rides.filter(r => r.status === 'ongoing').length} iconColor="text-blue-600" iconBg="bg-blue-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && fetchRides()}
                placeholder="Search rides..." className="bg-transparent text-sm outline-none w-full" />
            </div>
            <select aria-label="Filter by status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Status</option>
              <option value="completed">Completed</option>
              <option value="ongoing">Ongoing</option>
              <option value="pending">Pending</option>
              <option value="cancelled">Cancelled</option>
            </select>
            <select aria-label="Filter by service" value={serviceFilter} onChange={e => setServiceFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Services</option>
              <option value="taxi">Taxi</option>
              <option value="rental">Rental</option>
              <option value="outstation">Outstation</option>
              <option value="delivery">Delivery</option>
            </select>
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
                    {['Rider', 'Driver', 'Pickup → Drop', 'Service', 'Fare', 'Payment', 'Status', 'Date'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3 whitespace-nowrap">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 text-gray-800">{r.riderName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                        {r.pickupAddress}
                        {Array.isArray(r.stops) && r.stops.length > 0 && <span className="text-orange-600"> → +{r.stops.length} stop{r.stops.length > 1 ? 's' : ''}</span>}
                        {' → '}{r.dropAddress}
                        {r.waitingChargeTotal > 0 && <span className="text-purple-600"> · wait ₹{r.waitingChargeTotal}</span>}
                      </td>
                      <td className="px-4 py-3 text-gray-600 capitalize">{r.service}</td>
                      <td className="px-4 py-3 font-semibold text-gray-800">₹{r.fare}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs capitalize">{r.paymentMode}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                      <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">{r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'}</td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={8} className="text-center text-gray-400 py-12">No rides found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
      {toast && <Toast message={toast.msg} type="info" onClose={() => setToast(null)} />}
    </div>
  )
}
