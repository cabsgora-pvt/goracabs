'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { RidesPager } from '@/components/rides/pager'
import { SearchBox } from '@/components/rides/search-box'
import { useRideList } from '@/components/rides/use-ride-list'
import { fmtISTShort, rideHref } from '@/components/rides/format'
import { UserCog, Activity, Timer } from 'lucide-react'

export default function HireRidesPage() {
  const router = useRouter()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const { rides, total, stats, page, setPage, loading, error, limit } = useRideList({ service: 'hire_driver', status: statusFilter, search })
  const ph = stats?.byPhase || {}

  return (
    <div>
      <Header title="Hire a Driver" />
      <div className="p-6 space-y-6">
        <PageHeader title="Hire a Driver Rides" subtitle={stats ? `${stats.total} bookings · ₹${stats.revenue} from completed bookings` : 'Loading…'} />
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatBox label="Total" value={stats?.total ?? '…'} icon={UserCog} color="text-indigo-600 bg-indigo-50" />
          <StatBox label="Active now" value={stats ? (ph.ongoing || 0) + (ph.overtime || 0) : '…'} icon={Activity} color="text-green-600 bg-green-50" />
          <StatBox label="Completed" value={stats ? stats.byStatus?.completed || 0 : '…'} icon={Timer} color="text-purple-600 bg-purple-50" />
          <StatBox label="Revenue (completed)" value={stats ? `₹${stats.revenue}` : '…'} icon={Timer} color="text-orange-600 bg-orange-50" />
        </div>
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex flex-wrap gap-3">
          <SearchBox value={search} onSearch={setSearch} placeholder="Search rider, driver, phone, vehicle" />
          <select aria-label="Status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)} className="px-3 py-2 border border-gray-200 rounded-lg text-sm">
            <option value="all">All status</option><option value="pending">Pending</option><option value="accepted">Accepted</option><option value="ongoing">Ongoing</option><option value="completed">Completed</option><option value="cancelled">Cancelled</option>
          </select>
        </div>
        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
          {error && <p className="px-4 py-3 text-sm text-red-600 bg-red-50">{error}</p>}
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b"><tr>
              <Th>Date (IST)</Th><Th>Rider</Th><Th>Vehicle</Th><Th>Trans.</Th><Th>Booked</Th><Th>Worked</Th><Th>Driver</Th><Th>Base</Th><Th>Overtime</Th><Th>Final</Th><Th>Status</Th>
            </tr></thead>
            <tbody className="divide-y">
              {loading && <tr><td colSpan={11} className="text-center py-12 text-gray-400">Loading...</td></tr>}
              {!loading && rides.length === 0 && <tr><td colSpan={11} className="text-center py-12 text-gray-400">No hire rides.</td></tr>}
              {!loading && rides.map(r => (
                <tr key={r._id} className="hover:bg-gray-50 cursor-pointer" onClick={() => router.push(rideHref(r._id))}>
                  <Td><Link href={rideHref(r._id)} onClick={e => e.stopPropagation()} className="text-blue-600 hover:underline">{fmtISTShort(r.createdAt)}</Link></Td>
                  <Td className="font-semibold text-gray-900">{r.riderName || '—'}</Td>
                  <Td>{r.vehicleType || '—'}</Td>
                  <Td className="capitalize">{r.transmission || '—'}</Td>
                  <Td>{r.hireTotalHours || 0}hr</Td>
                  <Td>{(r.hireActualHours || 0).toFixed(1)}hr</Td>
                  <Td>{r.driverName || <span className="text-gray-400">Unassigned</span>}</Td>
                  <Td className="text-gray-700">₹{r.fare || 0}</Td>
                  <Td className={r.hireExtraCharge > 0 ? 'text-orange-600 font-semibold' : 'text-gray-400'}>₹{r.hireExtraCharge || 0}</Td>
                  <Td className="font-semibold text-indigo-700">₹{r.hireFinalFare || r.totalFare || r.fare || 0}</Td>
                  <Td><span className={`px-2 py-0.5 rounded text-xs font-semibold ${r.status === 'completed' ? 'bg-green-50 text-green-700' : r.status === 'cancelled' ? 'bg-red-50 text-red-700' : r.status === 'ongoing' ? 'bg-blue-50 text-blue-700' : 'bg-gray-100 text-gray-600'}`}>{r.status}</span></Td>
                </tr>
              ))}
            </tbody>
          </table>
          <RidesPager page={page} limit={limit} total={total} onPage={setPage} loading={loading} />
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
