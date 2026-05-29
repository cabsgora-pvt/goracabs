'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { TrendingUp, DollarSign, Wallet, BarChart2 } from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  PieChart, Pie, Cell, ResponsiveContainer
} from 'recharts'

const PIE_COLORS = ['#1565C0', '#43A047', '#FB8C00', '#E53935', '#8E24AA']

export default function ReportsPage() {
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [data, setData] = useState<any>(null)
  const [loading, setLoading] = useState(false)

  const fetchReport = () => {
    setLoading(true)
    const params = new URLSearchParams()
    if (dateFrom) params.set('dateFrom', dateFrom)
    if (dateTo) params.set('dateTo', dateTo)
    fetch(`/api/finance/reports?${params}`)
      .then(r => r.json())
      .then(d => { setData(d); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchReport() }, [])

  const grossRevenue = data?.grossRevenue || 0
  const commission = data?.commission || 0
  const driverPayout = data?.driverPayout || 0
  const netRevenue = data?.netRevenue || 0
  const byService = (data?.byService || []).map((s: any) => ({ service: s.service || s._id, revenue: s.revenue }))
  const byPayment = (data?.byPayment || []).map((p: any) => ({ name: p.mode || p._id, value: p.count || 0 }))
  const topDrivers = data?.topDrivers || []

  return (
    <div>
      <Header title="Reports" />
      <div className="p-6 space-y-6">
        <PageHeader title="Revenue Reports" subtitle="Analyze your revenue and performance metrics" />

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 flex flex-wrap items-center gap-4">
          <div>
            <label htmlFor="dateFrom" className="block text-xs text-gray-500 mb-1">From Date</label>
            <input id="dateFrom" type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)}
              className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          <div>
            <label htmlFor="dateTo" className="block text-xs text-gray-500 mb-1">To Date</label>
            <input id="dateTo" type="date" value={dateTo} onChange={e => setDateTo(e.target.value)}
              className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
          </div>
          <div className="self-end">
            <button type="button" onClick={fetchReport} disabled={loading}
              className="px-5 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
              {loading ? 'Loading...' : 'Generate Report'}
            </button>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={TrendingUp} label="Gross Revenue" value={`₹${grossRevenue.toLocaleString()}`} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={DollarSign} label="Commission (20%)" value={`₹${commission.toLocaleString()}`} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={Wallet} label="Driver Payout" value={`₹${driverPayout.toLocaleString()}`} iconColor="text-purple-600" iconBg="bg-purple-50" />
          <StatsCard icon={BarChart2} label="Net Revenue" value={`₹${netRevenue.toLocaleString()}`} iconColor="text-orange-600" iconBg="bg-orange-50" />
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Revenue by Service</h3>
            {byService.length > 0 ? (
              <ResponsiveContainer width="100%" height={220}>
                <BarChart data={byService}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#f0f4f8" />
                  <XAxis dataKey="service" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="revenue" fill="#1565C0" radius={[4, 4, 0, 0]} name="Revenue (₹)" />
                </BarChart>
              </ResponsiveContainer>
            ) : (
              <div className="h-48 flex items-center justify-center text-gray-400 text-sm">No revenue data</div>
            )}
          </div>

          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Revenue by Payment Mode</h3>
            {byPayment.length > 0 ? (
              <div className="flex items-center justify-center gap-8">
                <ResponsiveContainer width="50%" height={200}>
                  <PieChart>
                    <Pie data={byPayment} cx="50%" cy="50%" innerRadius={50} outerRadius={80}
                      dataKey="value" nameKey="name">
                      {byPayment.map((_: any, i: number) => (
                        <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                      ))}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
                <div className="space-y-2">
                  {byPayment.map((d: any, i: number) => (
                    <div key={d.name} className="flex items-center gap-2 text-sm">
                      <div className="w-3 h-3 rounded-full flex-shrink-0" style={{ background: PIE_COLORS[i % PIE_COLORS.length] }} />
                      <span className="text-gray-600 capitalize">{d.name}</span>
                      <span className="font-semibold text-gray-800">{d.value}</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <div className="h-48 flex items-center justify-center text-gray-400 text-sm">No payment data</div>
            )}
          </div>
        </div>

        {topDrivers.length > 0 && (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
            <h3 className="font-semibold text-gray-800 mb-4">Top 5 Drivers by Earnings</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-gray-100">
                    {['Rank', 'Driver', 'Total Rides', 'Earnings'].map(h => (
                      <th key={h} className="text-left text-xs text-gray-500 font-semibold pb-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {topDrivers.map((d: any, i: number) => (
                    <tr key={d._id} className="hover:bg-gray-50">
                      <td className="py-2.5">
                        <span className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${
                          i === 0 ? 'bg-yellow-100 text-yellow-700' :
                          i === 1 ? 'bg-gray-100 text-gray-600' :
                          i === 2 ? 'bg-orange-100 text-orange-700' : 'bg-blue-50 text-blue-600'
                        }`}>{i + 1}</span>
                      </td>
                      <td className="py-2.5 font-medium text-gray-800">{d.driverName || '—'}</td>
                      <td className="py-2.5 text-gray-600">{d.totalRides}</td>
                      <td className="py-2.5 font-semibold text-gray-800">₹{(d.totalEarnings || 0).toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
