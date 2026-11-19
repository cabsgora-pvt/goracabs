'use client'
import { useEffect, useState } from 'react'
import { Receipt, IndianRupee, Car, Activity } from 'lucide-react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { zoneFetch } from '@/components/zone-shell'

const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

export default function ZoneDashboard() {
  const [d, setD] = useState<any>(null)
  useEffect(() => { zoneFetch('/api/zone-admin/dashboard').then(r => r.json()).then(setD).catch(() => {}) }, [])

  return (
    <div>
      <Header title="Dashboard" />
      <div className="p-6 space-y-6">
        {!d ? <p className="text-gray-400">Loading…</p> : (
          <>
            <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4">
              <StatsCard icon={Receipt} label="Today's rides" value={d.todayRides} />
              <StatsCard icon={IndianRupee} label="Today's revenue" value={rupee(d.todayRevenue)} iconColor="text-green-600" iconBg="bg-green-50" />
              <StatsCard icon={Car} label="Drivers online" value={`${d.onlineDrivers} / ${d.drivers}`} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
              <StatsCard icon={Activity} label="Rides in progress" value={d.ongoingRides} iconColor="text-sky-600" iconBg="bg-sky-50" />
            </div>
            <div className="grid sm:grid-cols-2 gap-4">
              <StatsCard icon={Receipt} label="Completed rides (all time)" value={d.completedRides} />
              <StatsCard icon={IndianRupee} label="Ride revenue (all time)" value={rupee(d.totalRevenue)} iconColor="text-green-600" iconBg="bg-green-50" />
            </div>
            <div className="bg-white rounded shadow-sm">
              <div className="px-5 py-4 border-b border-[#e9ebec]"><h5 className="font-semibold text-[15px]">Recent rides</h5></div>
              <div className="overflow-x-auto">
                <table className="w-full text-[13px]">
                  <thead><tr>{['Rider', 'Driver', 'Route', 'Service', 'Fare', 'Status'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
                  <tbody className="divide-y">
                    {d.recentRides.length === 0 ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">No rides yet</td></tr> :
                      d.recentRides.map((r: any) => (
                        <tr key={r._id}>
                          <td className="px-4 py-3">{r.riderName || '—'}</td>
                          <td className="px-4 py-3">{r.driverName || '—'}</td>
                          <td className="px-4 py-3 max-w-[320px] truncate">{r.pickupAddress} → {r.dropAddress}</td>
                          <td className="px-4 py-3 capitalize">{(r.service || 'taxi').replace('_', ' ')} · {r.vehicleType}</td>
                          <td className="px-4 py-3">{rupee(r.totalFare)}</td>
                          <td className="px-4 py-3"><Badge status={r.status} /></td>
                        </tr>
                      ))}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
