'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { PageHeader } from '@/components/ui/page-header'
import { Search } from 'lucide-react'

export default function VehicleListPage() {
  const [vehicles, setVehicles] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [typeFilter, setTypeFilter] = useState('all')

  useEffect(() => {
    fetch('/api/vehicles/list')
      .then(r => r.json())
      .then(d => { setVehicles(d.vehicles || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const types = Array.from(new Set(vehicles.map((v: any) => v.vehicleType).filter(Boolean)))

  const filtered = vehicles.filter((v: any) => {
    const matchSearch = !search ||
      v.vehicleNumber?.toLowerCase().includes(search.toLowerCase()) ||
      v.vehicleModel?.toLowerCase().includes(search.toLowerCase()) ||
      v.name?.toLowerCase().includes(search.toLowerCase())
    const matchType = typeFilter === 'all' || v.vehicleType === typeFilter
    return matchSearch && matchType
  })

  return (
    <div>
      <Header title="All Vehicles" />
      <div className="p-6 space-y-6">
        <PageHeader title="All Vehicles" subtitle="View and filter all registered vehicles" />

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search by number, model, driver..."
                className="bg-transparent text-sm outline-none w-full" />
            </div>
            <select aria-label="Filter by vehicle type" value={typeFilter} onChange={e => setTypeFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Types</option>
              {types.map(t => <option key={t} value={t}>{t}</option>)}
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
                    {['Vehicle Number', 'Model', 'Type', 'Driver', 'Status', 'Registered'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map((v: any) => (
                    <tr key={v._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-mono text-gray-800 font-medium">{v.vehicleNumber || '—'}</td>
                      <td className="px-4 py-3 text-gray-700">{v.vehicleModel || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{v.vehicleType || '—'}</td>
                      <td className="px-4 py-3 text-gray-700">{v.name || '—'}</td>
                      <td className="px-4 py-3"><Badge status={v.status} /></td>
                      <td className="px-4 py-3 text-gray-500 text-xs">
                        {v.createdAt ? new Date(v.createdAt).toLocaleDateString() : '—'}
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={6} className="text-center text-gray-400 py-12">No vehicles found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
