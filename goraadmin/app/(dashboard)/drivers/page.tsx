'use client'
import { useState, useEffect, useCallback } from 'react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Pager } from '@/components/ui/pager'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Users, Car, Eye, Ban, Search, Star, Trash2 } from 'lucide-react'
import Link from 'next/link'

const LIMIT = 50
const inr = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

export default function DriversPage() {
  const [drivers, setDrivers] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [counts, setCounts] = useState<Record<string, number>>({})
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [appliedSearch, setAppliedSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [zoneFilter, setZoneFilter] = useState('')
  const [onlineFilter, setOnlineFilter] = useState('')
  const [vehicleFilter, setVehicleFilter] = useState('')
  const [walletFilter, setWalletFilter] = useState('')
  // Set by dashboard links (?filter=held / ?filter=negative)
  const [quickFilter, setQuickFilter] = useState<string>('')
  const [ready, setReady] = useState(false)
  useEffect(() => { setQuickFilter(new URLSearchParams(window.location.search).get('filter') || ''); setReady(true) }, [])
  const [zones, setZones] = useState<any[]>([])
  const [vehicleTypes, setVehicleTypes] = useState<string[]>([])
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [deleting, setDeleting] = useState<any | null>(null)

  useEffect(() => {
    fetch('/api/zones').then(r => r.json()).then(d => setZones(d.zones || [])).catch(() => {})
    fetch('/api/vehicles/types').then(r => r.json())
      .then(d => setVehicleTypes(Array.from(new Set((d.types || []).map((t: any) => String(t.name || '')).filter(Boolean))) as string[]))
      .catch(() => {})
  }, [])

  const fetchDrivers = useCallback(() => {
    setLoading(true)
    const params = new URLSearchParams({ page: String(page), limit: String(LIMIT) })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    if (quickFilter) params.set('filter', quickFilter)
    if (appliedSearch) params.set('search', appliedSearch)
    if (zoneFilter) params.set('zoneId', zoneFilter)
    if (onlineFilter) params.set('online', onlineFilter)
    if (vehicleFilter) params.set('vehicle', vehicleFilter)
    if (walletFilter) params.set('wallet', walletFilter)
    fetch(`/api/drivers?${params}`)
      .then(r => r.json())
      .then(d => { setDrivers(d.drivers || []); setTotal(d.total || 0); setCounts(d.counts || {}); setLoading(false) })
      .catch(() => setLoading(false))
  }, [page, statusFilter, quickFilter, appliedSearch, zoneFilter, onlineFilter, vehicleFilter, walletFilter])

  useEffect(() => { if (ready) fetchDrivers() }, [fetchDrivers, ready])
  const setFilter = (fn: (v: string) => void) => (v: string) => { setPage(1); fn(v) }

  const deleteDriver = async (id: string) => {
    const res = await fetch(`/api/drivers/${id}`, { method: 'DELETE' })
    if (res.ok) {
      setDeleting(null)
      setToast({ msg: 'Driver deleted', type: 'success' })
      fetchDrivers()
    } else {
      const d = await res.json().catch(() => ({}))
      setToast({ msg: d.error || 'Delete failed', type: 'error' })
    }
  }

  const toggleBlock = async (id: string, current: string) => {
    const newStatus = current !== 'blocked' ? 'blocked' : 'approved'
    const res = await fetch(`/api/drivers/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: newStatus }),
    })
    if (res.ok) {
      setDrivers(prev => prev.map((d: any) => d._id === id ? { ...d, status: newStatus } : d))
      setToast({ msg: 'Driver status updated', type: 'success' })
    } else {
      const d = await res.json().catch(() => ({}))
      setToast({ msg: d.error || 'Update failed', type: 'error' })
    }
  }

  const sel = 'border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500'

  return (
    <div>
      <Header title="Drivers" />
      {quickFilter && (
        <div className="px-6 pt-4">
          <span className="inline-flex items-center gap-2 bg-primary/10 text-primary text-xs font-semibold px-3 py-1.5 rounded-full">
            Showing: {({ held: 'Drivers on hold', negative: 'Negative wallet' } as Record<string, string>)[quickFilter] || quickFilter}
            <button type="button" aria-label="Clear filter" onClick={() => { setPage(1); setQuickFilter(''); window.history.replaceState(null, '', window.location.pathname) }} className="hover:text-red-600">✕</button>
          </span>
        </div>
      )}
      <div className="p-6 space-y-6">
        <PageHeader title="All Drivers" subtitle="Manage approved and registered drivers" />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-5 gap-4">
          <StatsCard icon={Users} label="All Drivers" value={counts.all || 0} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={Car} label="Approved" value={counts.approved || 0} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={Car} label="Pending" value={counts.pending || 0} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={Ban} label="Blocked" value={counts.blocked || 0} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={Ban} label="Rejected" value={counts.rejected || 0} iconColor="text-gray-600" iconBg="bg-gray-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') { setPage(1); setAppliedSearch(search.trim()) } }}
                onBlur={() => { if (search.trim() !== appliedSearch) { setPage(1); setAppliedSearch(search.trim()) } }}
                placeholder="Search name, phone, vehicle no. (Enter)" aria-label="Search drivers" className="bg-transparent text-sm outline-none w-full" />
            </div>
            <select aria-label="Filter by status" value={statusFilter} onChange={e => setFilter(setStatusFilter)(e.target.value)} className={sel}>
              <option value="all">All Status</option>
              <option value="approved">Approved</option>
              <option value="pending">Pending</option>
              <option value="blocked">Blocked</option>
              <option value="rejected">Rejected</option>
            </select>
            <select aria-label="Filter by zone" value={zoneFilter} onChange={e => setFilter(setZoneFilter)(e.target.value)} className={sel}>
              <option value="">All Zones</option>
              <option value="none">No zone</option>
              {zones.map(z => <option key={z._id} value={z._id}>{z.name}</option>)}
            </select>
            <select aria-label="Filter by online" value={onlineFilter} onChange={e => setFilter(setOnlineFilter)(e.target.value)} className={sel}>
              <option value="">Online + offline</option>
              <option value="1">Online now</option>
              <option value="0">Offline</option>
            </select>
            <select aria-label="Filter by vehicle type" value={vehicleFilter} onChange={e => setFilter(setVehicleFilter)(e.target.value)} className={sel}>
              <option value="">All Vehicles</option>
              {vehicleTypes.map(v => <option key={v} value={v}>{v}</option>)}
            </select>
            <select aria-label="Filter by wallet" value={walletFilter} onChange={e => setFilter(setWalletFilter)(e.target.value)} className={sel}>
              <option value="">Any wallet</option>
              <option value="negative">Wallet below ₹0</option>
            </select>
          </div>

          {loading && drivers.length === 0 ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className={`overflow-x-auto ${loading ? 'opacity-60' : ''}`}>
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Driver', 'Phone', 'Vehicle', 'Type', 'Zone', 'Online', 'Wallet', 'Rating', 'Rides', 'Status', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {drivers.map((d: any) => (
                    <tr key={d._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3">
                        <Link href={`/drivers/${d._id}`} className="flex items-center gap-3 hover:text-primary">
                          <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-700 font-semibold text-xs">
                            {d.name?.charAt(0) || '?'}
                          </div>
                          <span className="font-medium text-gray-800">{d.name || '—'}</span>
                        </Link>
                      </td>
                      <td className="px-4 py-3 text-gray-600">{d.phone}</td>
                      <td className="px-4 py-3 text-gray-700 font-mono text-xs">{d.vehicleNumber || d.vehicleRegistrationNumber || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{d.vehicleType || d.selectedVehicleTypeName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs">{d.zoneName || '—'}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex items-center gap-1 text-xs ${d.isOnline ? 'text-green-700' : 'text-gray-400'}`}>
                          <span className={`w-2 h-2 rounded-full ${d.isOnline ? 'bg-green-500' : 'bg-gray-300'}`} />{d.isOnline ? 'Online' : 'Offline'}
                        </span>
                      </td>
                      <td className={`px-4 py-3 font-medium whitespace-nowrap ${(d.walletBalance || 0) < 0 ? 'text-red-600' : 'text-gray-800'}`}>{inr(d.walletBalance)}</td>
                      <td className="px-4 py-3">
                        {d.rating > 0 ? (
                          <div className="flex items-center gap-1">
                            <Star className="w-3.5 h-3.5 text-yellow-400 fill-yellow-400" />
                            <span className="font-medium text-gray-800">{Number(d.rating).toFixed(1)}</span>
                          </div>
                        ) : <span className="text-gray-400">N/A</span>}
                      </td>
                      <td className="px-4 py-3 font-medium text-gray-800">{d.totalRides || 0}</td>
                      <td className="px-4 py-3"><Badge status={d.status} /></td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <Link href={`/drivers/${d._id}`} title="Open driver" className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600">
                            <Eye className="w-4 h-4" />
                          </Link>
                          <button type="button" onClick={() => toggleBlock(d._id, d.status)}
                            title={d.status !== 'blocked' ? 'Block driver' : 'Unblock driver'}
                            className={`p-1.5 rounded-lg ${d.status !== 'blocked' ? 'hover:bg-red-50 text-red-500' : 'hover:bg-green-50 text-green-600'}`}>
                            <Ban className="w-4 h-4" />
                          </button>
                          <button type="button" onClick={() => setDeleting(d)}
                            title="Delete driver"
                            className="p-1.5 hover:bg-red-50 rounded-lg text-red-500">
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                  {drivers.length === 0 && (
                    <tr><td colSpan={11} className="text-center text-gray-400 py-12">No drivers found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
          <div className="px-4 border-t border-gray-100">
            <Pager page={page} limit={LIMIT} total={total} onPage={setPage} noun={['driver', 'drivers']} />
          </div>
        </div>
      </div>
      {deleting && (
        <ConfirmDialog title="Delete driver" confirmLabel="Delete driver"
          message={<>Delete driver <strong>{deleting.name || deleting.phone}</strong>? This cannot be undone.</>}
          onConfirm={() => deleteDriver(deleting._id)} onClose={() => setDeleting(null)} />
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
