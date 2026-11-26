'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { TrendingUp, DollarSign, Wallet, BarChart2, Download } from 'lucide-react'
import { toCsv, downloadText } from '@/lib/csv'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip,
  PieChart, Pie, Cell, ResponsiveContainer
} from 'recharts'

const PIE_COLORS = ['#405189', '#43A047', '#FB8C00', '#E53935', '#8E24AA']
const inr = (n: any) => `₹${(Math.round((Number(n) || 0) * 100) / 100).toLocaleString('en-IN')}`

// The period figures, each with what it means (api/finance/reports, lib/finance).
const FIGURES: { key: string; label: string; help: string; tone?: string }[] = [
  { key: 'platformNet', label: 'Platform net (Gora keeps)', tone: 'text-green-700', help: 'Commission + subscriptions + cancellation fees kept − franchise shares − refunds on completed rides − coupon cost.' },
  { key: 'grossRevenue', label: 'Gross revenue (collected)', help: 'Fares of completed rides whose payment was collected.' },
  { key: 'commission', label: 'Ride commission', help: 'Commission on collected rides, before the franchise share.' },
  { key: 'driverPayout', label: 'Driver payout', help: 'Driver earnings on collected rides.' },
  { key: 'pendingRevenue', label: 'Pending (completed, unpaid)', tone: 'text-amber-700', help: 'Completed rides still waiting for payment — not yet in revenue.' },
  { key: 'subscriptionRevenue', label: 'Subscription revenue', help: 'Driver passes bought in the period (by purchase time).' },
  { key: 'cancellationFeesCollected', label: 'Cancellation fees kept', help: 'The part of a prepaid booking kept when the rider cancelled.' },
  { key: 'refunds', label: 'Refunds', tone: 'text-red-600', help: 'Wallet refunds credited. Only refunds of completed-ride money reduce platform net.' },
  { key: 'couponCost', label: 'Coupon cost', tone: 'text-red-600', help: 'Gora-funded coupon discounts on collected rides.' },
  { key: 'franchiseShare', label: 'Franchise share (rides)', help: "Zone admins' part of ride commission." },
  { key: 'netRevenue', label: 'Commission net of franchise', help: 'Ride commission − franchise share (the old “net revenue”).' },
]

export default function ReportsPage() {
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [data, setData] = useState<any>(null)
  const [summary, setSummary] = useState<any>(null)
  const [loading, setLoading] = useState(false)
  const [zoneId, setZoneId] = useState('')
  const [zones, setZones] = useState<any[]>([])
  useEffect(() => { fetch('/api/zones').then(r => r.json()).then(d => setZones(d.zones || [])).catch(() => {}) }, [])

  const fetchReport = () => {
    setLoading(true)
    const params = new URLSearchParams()
    if (dateFrom) params.set('dateFrom', dateFrom)
    if (dateTo) params.set('dateTo', dateTo)
    if (zoneId) params.set('zoneId', zoneId)
    fetch(`/api/finance/reports?${params}`)
      .then(r => r.json())
      .then(d => { setData(d); setLoading(false) })
      .catch(() => setLoading(false))
  }

  const fetchSummary = () => {
    fetch('/api/finance/summary')
      .then(r => r.json())
      .then(d => setSummary(d))
      .catch(() => {})
  }

  useEffect(() => { fetchReport(); fetchSummary() }, [])

  const zoneName = zones.find(z => z._id === (data?.zoneId || ''))?.name || ''
  const exportCsv = () => {
    if (!data) return
    const period = `${dateFrom || 'start'} to ${dateTo || 'today'}`
    const rows: unknown[][] = [
      ['Period (IST)', period, ''], ['Zone', zoneName || 'All zones', ''],
      ['Completed rides', data.completedRides ?? '', ''], ['Collected rides', data.totalRides ?? '', ''], ['Pending rides', data.pendingRides ?? '', ''],
      ...FIGURES.map(f => [f.label, data[f.key] ?? 0, f.help]),
      ...(data.byService || []).map((x: any) => [`Revenue · ${x.service || 'taxi'}`, x.revenue, `${x.count} rides`]),
      ...(data.byPayment || []).map((x: any) => [`Revenue · ${x.mode || 'unknown'} payments`, x.revenue, `${x.count} rides`]),
    ]
    downloadText(`gora-finance-${dateFrom || 'all'}-${dateTo || 'today'}${zoneName ? '-' + zoneName.replace(/\W+/g, '_') : ''}.csv`, toCsv(['Figure', 'Value (INR)', 'Meaning'], rows))
  }
  const byService = (data?.byService || []).map((s: any) => ({ service: s.service || s._id, revenue: s.revenue }))
  const byPayment = (data?.byPayment || []).map((p: any) => ({ name: p.mode || p._id, value: p.count || 0 }))
  const topDrivers = data?.topDrivers || []

  return (
    <div>
      <Header title="Reports" />
      <div className="p-6 space-y-6">
        <PageHeader title="Revenue Reports" subtitle="Analyze your revenue and performance metrics" />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={DollarSign} label="Admin Commission Profit" value={`₹${(summary?.totalCommission || 0).toLocaleString()}`} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={TrendingUp} label="Gross Revenue (All Time)" value={`₹${(summary?.grossRevenue || 0).toLocaleString()}`} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={Wallet} label="Total Driver Payout" value={`₹${(summary?.totalDriverPayout || 0).toLocaleString()}`} iconColor="text-purple-600" iconBg="bg-purple-50" />
          <StatsCard icon={BarChart2} label="Today's Commission" value={`₹${(summary?.todayCommission || 0).toLocaleString()}`} iconColor="text-orange-600" iconBg="bg-orange-50" />
        </div>

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
          <div>
            <label htmlFor="zoneSel" className="block text-xs text-gray-500 mb-1">Zone</label>
            <select id="zoneSel" value={zoneId} onChange={e => setZoneId(e.target.value)}
              className="border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="">All zones</option>
              {zones.map(z => <option key={z._id} value={z._id}>{z.name}</option>)}
            </select>
          </div>
          <div className="self-end flex gap-2">
            <button type="button" onClick={fetchReport} disabled={loading}
              className="px-5 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
              {loading ? 'Loading...' : 'Generate Report'}
            </button>
            <button type="button" onClick={exportCsv} disabled={!data || loading}
              className="px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium hover:bg-gray-50 disabled:opacity-50 flex items-center gap-2">
              <Download className="w-4 h-4" /> Export CSV
            </button>
          </div>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="px-5 py-3 border-b border-gray-100 flex flex-wrap items-center gap-2">
            <h3 className="font-semibold text-gray-800">Period figures</h3>
            <span className="text-xs text-gray-500">
              {dateFrom || dateTo ? `${dateFrom || 'start'} → ${dateTo || 'today'} (IST)` : 'All time'}{zoneName ? ` · ${zoneName}` : ' · all zones'}
              {data ? ` · ${data.completedRides ?? 0} completed rides (${data.totalRides ?? 0} paid, ${data.pendingRides ?? 0} unpaid)` : ''}
            </span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 divide-y sm:divide-y-0 gap-px bg-gray-100">
            {FIGURES.map(f => (
              <div key={f.key} className="bg-white p-4" data-figure={f.key}>
                <p className="text-xs text-gray-500">{f.label}</p>
                <p className={`text-xl font-bold mt-1 ${f.tone || 'text-gray-900'}`}>{data ? inr(data[f.key]) : '…'}</p>
                <p className="text-[11px] text-gray-400 mt-1 leading-snug">{f.help}</p>
              </div>
            ))}
          </div>
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
                  <Bar dataKey="revenue" fill="#405189" radius={[4, 4, 0, 0]} name="Revenue (₹)" />
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
