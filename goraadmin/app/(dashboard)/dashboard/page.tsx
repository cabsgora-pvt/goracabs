'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Users, Car, TrendingUp, DollarSign, Clock, AlertCircle, Wallet } from 'lucide-react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  BarChart, Bar, ResponsiveContainer
} from 'recharts'

export default function DashboardPage() {
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/dashboard')
      .then(r => r.json())
      .then(d => { setData(d); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  if (loading) return (
    <div>
      <Header title="Dashboard" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  const totalUsers = data?.totalUsers ?? 0
  const totalDrivers = data?.totalDrivers ?? 0
  const todayRides = data?.todayRides ?? 0
  const todayRevenue = data?.todayRevenue ?? 0
  const pendingApprovals = data?.pendingApprovals ?? 0
  const openTickets = data?.openTickets ?? 0
  const pendingWithdrawals = data?.pendingWithdrawals ?? 0
  const onlineDrivers = data?.onlineDrivers ?? 0
  const recentRides = data?.recentRides ?? []
  const chartData = data?.chartData ?? []
  const serviceData = data?.serviceData ?? []

  return (
    <div>
      <Header title="Dashboard" />
      <div className="p-6 space-y-6">
        {/* Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={Users} label="Total Users" value={totalUsers.toLocaleString()} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={Car} label="Total Drivers" value={totalDrivers.toLocaleString()} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={TrendingUp} label="Today's Rides" value={todayRides.toLocaleString()} iconColor="text-purple-600" iconBg="bg-purple-50" />
          <StatsCard icon={DollarSign} label="Today's Revenue" value={`₹${todayRevenue.toLocaleString()}`} iconColor="text-orange-600" iconBg="bg-orange-50" />
        </div>

        {/* Charts row */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          {/* Line chart */}
          <div className="xl:col-span-2 bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Rides & Revenue (Last 7 Days)</h3>
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0f4f8" />
                <XAxis dataKey="_id" tick={{ fontSize: 12 }} />
                <YAxis yAxisId="left" tick={{ fontSize: 12 }} />
                <YAxis yAxisId="right" orientation="right" tick={{ fontSize: 12 }} />
                <Tooltip />
                <Legend />
                <Line yAxisId="left" type="monotone" dataKey="rides" stroke="#1565C0" strokeWidth={2} dot={false} name="Rides" />
                <Line yAxisId="right" type="monotone" dataKey="revenue" stroke="#43A047" strokeWidth={2} dot={false} name="Revenue (₹)" />
              </LineChart>
            </ResponsiveContainer>
          </div>

          {/* Quick stats */}
          <div className="space-y-4">
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4">Alerts & Actions</h3>
              <div className="space-y-3">
                <div className="flex items-center justify-between p-3 bg-yellow-50 rounded-lg border border-yellow-100">
                  <div className="flex items-center gap-2">
                    <Clock className="w-4 h-4 text-yellow-600" />
                    <span className="text-sm text-yellow-800">Pending Approvals</span>
                  </div>
                  <span className="font-bold text-yellow-700">{pendingApprovals}</span>
                </div>
                <div className="flex items-center justify-between p-3 bg-red-50 rounded-lg border border-red-100">
                  <div className="flex items-center gap-2">
                    <AlertCircle className="w-4 h-4 text-red-600" />
                    <span className="text-sm text-red-800">Open Tickets</span>
                  </div>
                  <span className="font-bold text-red-700">{openTickets}</span>
                </div>
                <div className="flex items-center justify-between p-3 bg-blue-50 rounded-lg border border-blue-100">
                  <div className="flex items-center gap-2">
                    <Wallet className="w-4 h-4 text-blue-600" />
                    <span className="text-sm text-blue-800">Pending Withdrawals</span>
                  </div>
                  <span className="font-bold text-blue-700">{pendingWithdrawals}</span>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4">Driver Status</h3>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="w-2.5 h-2.5 rounded-full bg-green-500" />
                    <span className="text-sm text-gray-600">Online</span>
                  </div>
                  <span className="font-semibold text-gray-800">{onlineDrivers}</span>
                </div>
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <div className="w-2.5 h-2.5 rounded-full bg-gray-400" />
                    <span className="text-sm text-gray-600">Offline</span>
                  </div>
                  <span className="font-semibold text-gray-800">{Math.max(0, totalDrivers - onlineDrivers)}</span>
                </div>
              </div>
              {totalDrivers > 0 && (
                <>
                  <div className="mt-3 h-2 bg-gray-100 rounded-full overflow-hidden">
                    <div className="h-full bg-green-500 rounded-full" style={{ width: `${Math.round((onlineDrivers / totalDrivers) * 100)}%` }} />
                  </div>
                  <p className="text-xs text-gray-400 mt-1">{Math.round((onlineDrivers / totalDrivers) * 100)}% online</p>
                </>
              )}
            </div>
          </div>
        </div>

        {/* Revenue by service + Recent rides */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Revenue by Service</h3>
            {serviceData.length > 0 ? (
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={serviceData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f4f8" />
                  <XAxis dataKey="service" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="revenue" fill="#1565C0" radius={[4, 4, 0, 0]} name="Revenue (₹)" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-48 flex items-center justify-center text-gray-400 text-sm">No revenue data yet</div>
            )}
          </div>

          <div className="xl:col-span-2 bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Recent Rides</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-100">
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Rider</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Route</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Fare</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {recentRides.map((r: any) => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="py-2.5 text-gray-700">{r.riderName || '—'}</td>
                      <td className="py-2.5 text-gray-500 text-xs">{r.pickupAddress} → {r.dropAddress}</td>
                      <td className="py-2.5 font-medium text-gray-800">₹{r.fare}</td>
                      <td className="py-2.5"><Badge status={r.status} /></td>
                    </tr>
                  ))}
                  {recentRides.length === 0 && (
                    <tr><td colSpan={4} className="py-8 text-center text-gray-400">No rides yet</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
