'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Users, Car, Eye, Ban, Search, Star, Trash2 } from 'lucide-react'
import Link from 'next/link'

export default function DriversPage() {
  const [drivers, setDrivers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [vehicleFilter, setVehicleFilter] = useState('all')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchDrivers = () => {
    setLoading(true)
    const params = new URLSearchParams({ limit: '100' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    if (search) params.set('search', search)
    fetch(`/api/drivers?${params}`)
      .then(r => r.json())
      .then(d => { setDrivers(d.drivers || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchDrivers() }, [statusFilter])

  const vehicleTypes = Array.from(new Set(drivers.map((d: any) => d.vehicleType).filter(Boolean)))

  const filtered = drivers.filter((d: any) => {
    const matchSearch = !search || d.name?.toLowerCase().includes(search.toLowerCase()) ||
      d.phone?.includes(search) || d.vehicleNumber?.toLowerCase().includes(search.toLowerCase())
    const matchVehicle = vehicleFilter === 'all' || d.vehicleType === vehicleFilter
    return matchSearch && matchVehicle
  })

  const deleteDriver = async (id: string, name: string) => {
    if (!confirm(`Delete driver "${name}"? This cannot be undone.`)) return
    const res = await fetch(`/api/drivers/${id}`, { method: 'DELETE' })
    if (res.ok) {
      setDrivers(prev => prev.filter(d => d._id !== id))
      setToast({ msg: 'Driver deleted', type: 'success' })
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
    }
  }

  return (
    <div>
      <Header title="Drivers" />
      <div className="p-6 space-y-6">
        <PageHeader title="All Drivers" subtitle="Manage approved and registered drivers" />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={Users} label="Total Drivers" value={drivers.length} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={Car} label="Approved" value={drivers.filter((d: any) => d.status === 'approved').length} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={Car} label="Pending" value={drivers.filter((d: any) => d.status === 'pending').length} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={Ban} label="Blocked" value={drivers.filter((d: any) => d.status === 'blocked').length} iconColor="text-red-600" iconBg="bg-red-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && fetchDrivers()}
                placeholder="Search drivers..." className="bg-transparent text-sm outline-none w-full" />
            </div>
            <select aria-label="Filter by status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Status</option>
              <option value="approved">Approved</option>
              <option value="pending">Pending</option>
              <option value="blocked">Blocked</option>
            </select>
            <select aria-label="Filter by vehicle type" value={vehicleFilter} onChange={e => setVehicleFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Vehicles</option>
              {vehicleTypes.map(v => <option key={v} value={v}>{v}</option>)}
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
                    {['Driver', 'Phone', 'Vehicle', 'Type', 'Rating', 'Total Rides', 'Earnings', 'Status', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map((d: any) => (
                    <tr key={d._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-green-100 flex items-center justify-center text-green-700 font-semibold text-xs">
                            {d.name?.charAt(0) || '?'}
                          </div>
                          <span className="font-medium text-gray-800">{d.name}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-gray-600">{d.phone}</td>
                      <td className="px-4 py-3 text-gray-700 font-mono text-xs">{d.vehicleNumber}</td>
                      <td className="px-4 py-3 text-gray-600">{d.vehicleType}</td>
                      <td className="px-4 py-3">
                        {d.rating > 0 ? (
                          <div className="flex items-center gap-1">
                            <Star className="w-3.5 h-3.5 text-yellow-400 fill-yellow-400" />
                            <span className="font-medium text-gray-800">{d.rating}</span>
                          </div>
                        ) : <span className="text-gray-400">N/A</span>}
                      </td>
                      <td className="px-4 py-3 font-medium text-gray-800">{d.totalRides || 0}</td>
                      <td className="px-4 py-3 font-medium text-gray-800">₹{(d.totalEarnings || 0).toLocaleString()}</td>
                      <td className="px-4 py-3"><Badge status={d.status} /></td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <Link href={`/drivers/${d._id}`} className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600">
                            <Eye className="w-4 h-4" />
                          </Link>
                          <button type="button" onClick={() => toggleBlock(d._id, d.status)}
                            title={d.status !== 'blocked' ? 'Block driver' : 'Unblock driver'}
                            className={`p-1.5 rounded-lg ${d.status !== 'blocked' ? 'hover:bg-red-50 text-red-500' : 'hover:bg-green-50 text-green-600'}`}>
                            <Ban className="w-4 h-4" />
                          </button>
                          <button type="button" onClick={() => deleteDriver(d._id, d.name || d.phone)}
                            title="Delete driver"
                            className="p-1.5 hover:bg-red-50 rounded-lg text-red-500">
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={9} className="text-center text-gray-400 py-12">No drivers found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
