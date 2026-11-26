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
import { Clock, Timer, MapPin, Activity, AlertTriangle } from 'lucide-react'

export default function RentalRidesPage() {
  const router = useRouter()
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [anomalyOnly, setAnomalyOnly] = useState(false)
  const { rides, total, stats, page, setPage, loading, error, limit } = useRideList({
    service: 'rental', status: statusFilter, search, anomaly: anomalyOnly ? '1' : undefined,
  })

  const ph = stats?.byPhase || {}
  const active = (ph.ongoing || 0) + (ph.extra_time || 0) + (ph.paused || 0)

  return (
    <div>
      <Header title="Rental Rides" />
      <div className="p-6 space-y-6">
        <PageHeader title="Rental Rides" subtitle={stats ? `${stats.total} bookings · ₹${stats.revenue} from completed rides` : 'Loading…'} />

        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
          <StatBox label="Total" value={stats?.total ?? '…'} icon={Clock} color="text-blue-600 bg-blue-50" />
          <StatBox label="Active now" value={stats ? active : '…'} icon={Activity} color="text-green-600 bg-green-50" />
          <StatBox label="Completed" value={stats?.byStatus?.completed ?? (stats ? 0 : '…')} icon={Timer} color="text-purple-600 bg-purple-50" />
          <StatBox label="Revenue (completed)" value={stats ? `₹${stats.revenue}` : '…'} icon={MapPin} color="text-orange-600 bg-orange-50" />
          <button type="button" onClick={() => setAnomalyOnly(!anomalyOnly)} className="text-left">
            <StatBox label={anomalyOnly ? 'km anomalies (showing)' : 'km anomalies'} value={stats?.anomalies ?? '…'} icon={AlertTriangle} color={`text-red-600 bg-red-50 ${anomalyOnly ? 'ring-2 ring-red-300' : ''}`} />
          </button>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex flex-wrap gap-3 items-center">
          <SearchBox value={search} onSearch={setSearch} placeholder="Search rider, driver, phone, vehicle" />
          <select aria-label="Status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
            className="px-3 py-2 border border-gray-200 rounded-lg text-sm">
            <option value="all">All status</option>
            <option value="pending">Pending</option>
            <option value="accepted">Accepted</option>
            <option value="ongoing">Ongoing</option>
            <option value="completed">Completed</option>
            <option value="cancelled">Cancelled</option>
          </select>
          <label className="flex items-center gap-2 text-sm text-gray-700">
            <input type="checkbox" checked={anomalyOnly} onChange={e => setAnomalyOnly(e.target.checked)} aria-label="km anomalies only" />
            km anomalies only
          </label>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
          {error && <p className="px-4 py-3 text-sm text-red-600 bg-red-50">{error}</p>}
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b">
              <tr>
                <Th>Date (IST)</Th><Th>Rider</Th><Th>Vehicle</Th><Th>Package</Th><Th>Used</Th><Th>km expected</Th>
                <Th>Driver</Th><Th>Base</Th><Th>Extras</Th><Th>Final</Th><Th>Phase</Th><Th>Status</Th>
              </tr>
            </thead>
            <tbody className="divide-y">
              {loading && <tr><td colSpan={12} className="text-center py-12 text-gray-400">Loading...</td></tr>}
              {!loading && rides.length === 0 && <tr><td colSpan={12} className="text-center py-12 text-gray-400">No rental rides.</td></tr>}
              {!loading && rides.map(r => {
                const extras = (r.extraHoursCharge || 0) + (r.extraKmCharge || 0)
                return (
                  <tr key={r._id} className={`hover:bg-gray-50 cursor-pointer ${r.kmAnomaly ? 'bg-red-50/40' : ''}`} onClick={() => router.push(rideHref(r._id))}>
                    <Td><Link href={rideHref(r._id)} onClick={e => e.stopPropagation()} className="text-blue-600 hover:underline">{fmtISTShort(r.createdAt)}</Link></Td>
                    <Td className="font-semibold text-gray-900">{r.riderName || '—'}</Td>
                    <Td>{r.vehicleType || '—'}</Td>
                    <Td>{r.packageHours || 0}hr / {r.packageKm || 0}km</Td>
                    <Td>{(r.actualHours || 0).toFixed(1)}hr / {(r.actualKm || 0).toFixed(1)}km</Td>
                    <Td>
                      {r.kmExpected != null ? (
                        <span className={r.kmAnomaly ? 'text-red-600 font-semibold' : 'text-gray-700'}>
                          {r.kmExpected} km <span className="text-xs text-gray-500">vs {(r.actualKm || 0).toFixed(1)}</span>
                        </span>
                      ) : <span className="text-gray-400">—</span>}
                      {r.kmAnomaly && <span className="ml-1 px-1.5 py-0.5 rounded bg-red-100 text-red-700 text-[10px] font-bold uppercase">km anomaly</span>}
                    </Td>
                    <Td>{r.driverName || <span className="text-gray-400">Unassigned</span>}</Td>
                    <Td className="text-gray-700">₹{r.fare || 0}</Td>
                    <Td className={extras > 0 ? 'text-orange-600 font-semibold' : 'text-gray-400'}>₹{extras}</Td>
                    <Td className="font-semibold text-blue-700">₹{r.finalFare || r.totalFare || r.fare || 0}</Td>
                    <Td><span className="text-xs text-gray-500">{r.rentalPhase || '—'}</span></Td>
                    <Td>
                      <span className={`px-2 py-0.5 rounded text-xs font-semibold ${
                        r.status === 'completed' ? 'bg-green-50 text-green-700' :
                        r.status === 'cancelled' ? 'bg-red-50 text-red-700' :
                        r.status === 'ongoing' ? 'bg-blue-50 text-blue-700' :
                        'bg-gray-100 text-gray-600'}`}>{r.status}</span>
                    </Td>
                  </tr>
                )
              })}
            </tbody>
          </table>
          <RidesPager page={page} limit={limit} total={total} onPage={setPage} loading={loading} />
        </div>
      </div>
    </div>
  )
}

function StatBox({ label, value, icon: Icon, color }: any) {
  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex items-center gap-3 h-full">
      <div className={`p-3 rounded-lg ${color}`}><Icon className="w-5 h-5" /></div>
      <div><div className="text-xs text-gray-500">{label}</div><div className="text-xl font-bold text-gray-900">{value}</div></div>
    </div>
  )
}
function Th({ children }: any) { return <th className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3 whitespace-nowrap">{children}</th> }
function Td({ children, className = '' }: any) { return <td className={`px-4 py-3 ${className}`}>{children}</td> }
