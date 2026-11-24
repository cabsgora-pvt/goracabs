'use client'
import { useState, useEffect } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import {
  Users, Car, TrendingUp, IndianRupee, Clock, AlertCircle, Wallet, Radio, Search, XCircle, CalendarClock,
  UserPlus, ShieldAlert, PauseCircle, MinusCircle, Siren, Inbox, ChevronRight,
} from 'lucide-react'
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend,
  BarChart, Bar, ResponsiveContainer,
} from 'recharts'

const inr = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`
const SERVICE_LABEL: Record<string, string> = { taxi: 'Taxi', delivery: 'Parcel', rental: 'Rental', outstation: 'Outstation', hire_driver: 'Hire driver' }
const SERVICE_PAGE: Record<string, string> = { taxi: '/rides', delivery: '/rides/delivery', rental: '/rides/rental', outstation: '/rides/outstation', hire_driver: '/rides/hire' }

// Every number on this page opens the list behind it.
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

  const d = data || {}
  const n = (k: string) => Number(d[k] ?? 0)
  const recentRides = d.recentRides ?? []
  const chartData = d.chartData ?? []
  const serviceData = (d.serviceData ?? []).map((s: any) => ({ ...s, label: SERVICE_LABEL[s.service] || s.service }))
  const todayByService: any[] = d.todayByService ?? []

  const alert = (href: string, icon: any, label: string, value: number, tone: string) => {
    const Icon = icon
    return (
      <Link href={href} className={`flex items-center justify-between p-3 rounded-lg border transition hover:shadow-sm ${tone}`}>
        <span className="flex items-center gap-2 text-sm"><Icon className="w-4 h-4" />{label}</span>
        <span className="flex items-center gap-1 font-bold">{value}<ChevronRight className="w-4 h-4 opacity-50" /></span>
      </Link>
    )
  }

  return (
    <div>
      <Header title="Dashboard" />
      <div className="p-6 space-y-6">
        {/* Today */}
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard href="/rides" icon={TrendingUp} label="Today's Rides" value={n('todayRides').toLocaleString()}
            sub={`${n('todayCompleted')} completed · ${n('todayCancelled')} cancelled`} iconColor="text-purple-600" iconBg="bg-purple-50" />
          <StatsCard href="/finance/reports" icon={IndianRupee} label="Today's Revenue" value={inr(n('todayRevenue'))}
            sub={`${inr(n('todayCommission'))} commission`} iconColor="text-orange-600" iconBg="bg-orange-50" />
          <StatsCard href="/rides/ongoing" icon={Radio} label="Rides live now" value={n('liveNow')}
            sub={`${n('searchingNow')} searching for a driver`} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard href="/drivers" icon={Car} label="Drivers online" value={`${n('onlineDrivers')} / ${n('totalDrivers')}`}
            sub={`${n('totalDrivers') ? Math.round((n('onlineDrivers') / n('totalDrivers')) * 100) : 0}% of approved drivers`} iconColor="text-blue-600" iconBg="bg-blue-50" />
        </div>

        {/* Week / month / people */}
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard href="/finance/reports" icon={IndianRupee} label="Last 7 days revenue" value={inr(n('weekRevenue'))}
            sub={`${n('weekCompleted')} trips · ${inr(n('weekCommission'))} commission`} iconColor="text-teal-600" iconBg="bg-teal-50" />
          <StatsCard href="/finance/reports" icon={IndianRupee} label="This month revenue" value={inr(n('monthRevenue'))}
            sub={`${inr(n('monthCommission'))} commission`} iconColor="text-indigo-600" iconBg="bg-indigo-50" />
          <StatsCard href="/users" icon={Users} label="Riders" value={n('totalUsers').toLocaleString()}
            sub={`+${n('newRidersToday')} today · +${n('newRidersWeek')} this week`} iconColor="text-sky-600" iconBg="bg-sky-50" />
          <StatsCard href="/drivers/pending" icon={UserPlus} label="New drivers (7 days)" value={n('newDriversWeek')}
            sub={`${n('pendingApprovals')} waiting for approval`} iconColor="text-amber-600" iconBg="bg-amber-50" />
        </div>

        {/* Charts row */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
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
                <Line yAxisId="left" type="monotone" dataKey="rides" stroke="#405189" strokeWidth={2} dot={false} name="Rides" />
                <Line yAxisId="right" type="monotone" dataKey="revenue" stroke="#43A047" strokeWidth={2} dot={false} name="Revenue (₹)" />
              </LineChart>
            </ResponsiveContainer>
          </div>

          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Needs attention</h3>
            <div className="space-y-2.5">
              {alert('/support/sos', Siren, 'Active SOS', n('openSos'), 'bg-red-50 border-red-100 text-red-700')}
              {alert('/account-requests', Inbox, 'Account requests', n('pendingRequests'), 'bg-purple-50 border-purple-100 text-purple-700')}
              {alert('/drivers/pending', Clock, 'Driver approvals', n('pendingApprovals'), 'bg-yellow-50 border-yellow-100 text-yellow-800')}
              {alert('/support/tickets', AlertCircle, 'Open tickets', n('openTickets'), 'bg-orange-50 border-orange-100 text-orange-700')}
              {alert('/finance/withdrawals', Wallet, 'Pending withdrawals', n('pendingWithdrawals'), 'bg-blue-50 border-blue-100 text-blue-700')}
              {alert('/drivers?filter=held', PauseCircle, 'Drivers on hold', n('heldDrivers'), 'bg-gray-50 border-gray-200 text-gray-700')}
              {alert('/users?filter=held', ShieldAlert, 'Riders on hold', n('heldRiders'), 'bg-gray-50 border-gray-200 text-gray-700')}
              {alert('/drivers?filter=negative', MinusCircle, `Negative wallet (owe ${inr(n('driversOwe'))})`, n('negativeWalletDrivers'), 'bg-rose-50 border-rose-100 text-rose-700')}
            </div>
          </div>
        </div>

        {/* Services today + revenue by service + recent rides */}
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5 space-y-5">
            <div>
              <h3 className="font-semibold text-gray-800 mb-3">Today by service</h3>
              <div className="grid grid-cols-2 gap-2">
                {['taxi', 'delivery', 'rental', 'outstation', 'hire_driver'].map(s => (
                  <Link key={s} href={SERVICE_PAGE[s]} className="flex items-center justify-between px-3 py-2 rounded-lg bg-gray-50 hover:bg-gray-100 text-sm">
                    <span className="text-gray-600">{SERVICE_LABEL[s]}</span>
                    <span className="font-semibold text-gray-800">{todayByService.find(x => x.service === s)?.rides || 0}</span>
                  </Link>
                ))}
                <Link href="/rides/scheduled" className="flex items-center justify-between px-3 py-2 rounded-lg bg-gray-50 hover:bg-gray-100 text-sm">
                  <span className="text-gray-600 flex items-center gap-1"><CalendarClock className="w-3.5 h-3.5" />Scheduled</span>
                  <span className="font-semibold text-gray-800">{n('scheduledUpcoming')}</span>
                </Link>
              </div>
            </div>
            <div>
              <h3 className="font-semibold text-gray-800 mb-3">Revenue by service (7 days)</h3>
              {serviceData.length > 0 ? (
                <ResponsiveContainer width="100%" height={170}>
                  <BarChart data={serviceData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f0f4f8" />
                    <XAxis dataKey="label" tick={{ fontSize: 11 }} />
                    <YAxis tick={{ fontSize: 11 }} />
                    <Tooltip />
                    <Bar dataKey="revenue" fill="#405189" radius={[4, 4, 0, 0]} name="Revenue (₹)" />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="h-32 flex items-center justify-center text-gray-400 text-sm">No revenue data yet</div>
              )}
            </div>
          </div>

          <div className="xl:col-span-2 bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-gray-800">Recent Rides</h3>
              <Link href="/rides" className="text-xs text-primary hover:underline">View all</Link>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-100">
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Rider</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Route</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Service</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Fare</th>
                    <th className="text-left text-xs text-gray-500 font-semibold pb-3">Status</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {recentRides.map((r: any) => (
                    <tr key={r._id} className="hover:bg-gray-50 cursor-pointer" onClick={() => { window.location.href = SERVICE_PAGE[r.service || 'taxi'] || '/rides' }}>
                      <td className="py-2.5 text-gray-700">{r.riderName || '—'}</td>
                      <td className="py-2.5 text-gray-500 text-xs max-w-xs truncate">{r.pickupAddress} → {r.dropAddress}</td>
                      <td className="py-2.5 text-gray-600 text-xs">{SERVICE_LABEL[r.service || 'taxi'] || r.service}</td>
                      <td className="py-2.5 font-medium text-gray-800">₹{r.totalFare ?? r.fare}</td>
                      <td className="py-2.5"><Badge status={r.status} /></td>
                    </tr>
                  ))}
                  {recentRides.length === 0 && (
                    <tr><td colSpan={5} className="py-8 text-center text-gray-400">No rides yet</td></tr>
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
