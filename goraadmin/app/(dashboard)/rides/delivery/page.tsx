'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Package, Activity, CheckCircle, Search } from 'lucide-react'

export default function DeliveryRidesPage() {
  const [rides, setRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')

  const fetch_ = () => {
    setLoading(true)
    const params = new URLSearchParams({ limit: '200', service: 'delivery' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    fetch(`/api/rides?${params}`).then(r => r.json()).then(d => { setRides(d.rides || []); setLoading(false) }).catch(() => setLoading(false))
  }
  useEffect(() => { fetch_() }, [statusFilter])

  const filtered = rides.filter(r => {
    if (!search) return true
    const s = search.toLowerCase()
    return [r.senderName, r.receiverName, r.driverName, r.itemType].some(v => (v || '').toLowerCase().includes(s))
  })
  const totalFare = filtered.reduce((s, r) => s + (r.totalFare || r.fare || 0), 0)
  const active = filtered.filter(r => ['collected', 'in_transit'].includes(r.deliveryPhase)).length
  const delivered = filtered.filter(r => r.deliveryPhase === 'delivered' || r.status === 'completed').length

  return (
    <div>
      <Header title="Parcel Delivery" />
      <div className="p-6 space-y-6">
        <PageHeader title="Parcel Deliveries" subtitle={`${filtered.length} parcels · ₹${totalFare.toFixed(0)} total`} />
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatBox label="Total" value={filtered.length.toString()} icon={Package} color="text-teal-600 bg-teal-50" />
          <StatBox label="In transit" value={active.toString()} icon={Activity} color="text-blue-600 bg-blue-50" />
          <StatBox label="Delivered" value={delivered.toString()} icon={CheckCircle} color="text-green-600 bg-green-50" />
          <StatBox label="Revenue" value={`₹${totalFare.toFixed(0)}`} icon={Package} color="text-orange-600 bg-orange-50" />
        </div>
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex flex-wrap gap-3">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input type="text" placeholder="Search sender, receiver, driver, item..." value={search} onChange={e => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 border border-gray-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-teal-500" />
          </div>
          <select aria-label="Status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)} className="px-3 py-2 border border-gray-200 rounded-lg text-sm">
            <option value="all">All status</option><option value="pending">Pending</option><option value="ongoing">Ongoing</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option>
          </select>
        </div>
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b"><tr>
              <Th>Date</Th><Th>Sender</Th><Th>Receiver</Th><Th>Item</Th><Th>Wt</Th><Th>Vehicle</Th><Th>Driver</Th><Th>Fare</Th><Th>Phase</Th><Th>Status</Th>
            </tr></thead>
            <tbody className="divide-y">
              {loading && <tr><td colSpan={10} className="text-center py-12 text-gray-400">Loading...</td></tr>}
              {!loading && filtered.length === 0 && <tr><td colSpan={10} className="text-center py-12 text-gray-400">No deliveries.</td></tr>}
              {filtered.map(r => (
                <tr key={r._id} className="hover:bg-gray-50">
                  <Td>{r.createdAt ? new Date(r.createdAt).toLocaleString('en-IN', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' }) : '—'}</Td>
                  <Td className="font-semibold text-gray-900">{r.senderName || r.riderName || '—'}</Td>
                  <Td>{r.receiverName || '—'}</Td>
                  <Td>{r.itemType || '—'}</Td>
                  <Td>{r.weightKg || 0}kg</Td>
                  <Td>{r.vehicleType || '—'}</Td>
                  <Td>{r.driverName || <span className="text-gray-400">Unassigned</span>}</Td>
                  <Td className="font-semibold text-teal-700">₹{r.totalFare || r.fare || 0}</Td>
                  <Td><span className="text-xs text-gray-500">{r.deliveryPhase || '—'}</span></Td>
                  <Td><span className={`px-2 py-0.5 rounded text-xs font-semibold ${r.status === 'completed' ? 'bg-green-50 text-green-700' : r.status === 'cancelled' ? 'bg-red-50 text-red-700' : r.status === 'ongoing' ? 'bg-blue-50 text-blue-700' : 'bg-gray-100 text-gray-600'}`}>{r.status}</span></Td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
function StatBox({ label, value, icon: Icon, color }: any) {
  return <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex items-center gap-3">
    <div className={`p-3 rounded-lg ${color}`}><Icon className="w-5 h-5" /></div>
    <div><div className="text-xs text-gray-500">{label}</div><div className="text-xl font-bold text-gray-900">{value}</div></div></div>
}
function Th({ children }: any) { return <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{children}</th> }
function Td({ children, className = '' }: any) { return <td className={`px-4 py-3 ${className}`}>{children}</td> }
