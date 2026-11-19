'use client'
import { useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { zoneFetch } from '@/components/zone-shell'

const STATUSES = ['', 'pending', 'accepted', 'ongoing', 'completed', 'cancelled']
const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

export default function ZoneRides() {
  const [status, setStatus] = useState('')
  const [page, setPage] = useState(1)
  const [d, setD] = useState<any>(null)

  useEffect(() => {
    setD(null)
    zoneFetch(`/api/zone-admin/rides?page=${page}${status ? `&status=${status}` : ''}`).then(r => r.json()).then(setD).catch(() => {})
  }, [status, page])

  return (
    <div>
      <Header title="Rides" />
      <div className="p-6">
        <div className="bg-white rounded shadow-sm">
          <div className="p-4 border-b border-[#e9ebec] flex flex-wrap gap-2">
            {STATUSES.map(s => (
              <button key={s || 'all'} type="button" onClick={() => { setStatus(s); setPage(1) }}
                className={`px-3 py-1.5 rounded text-[13px] capitalize ${status === s ? 'bg-primary text-white' : 'bg-[#f3f6f9] text-[#495057]'}`}>
                {s || 'All'}
              </button>
            ))}
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-[13px]">
              <thead><tr>{['Date', 'Rider', 'Driver', 'Route', 'Service', 'Payment', 'Fare', 'Status'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {!d ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">Loading…</td></tr> :
                  d.rides.length === 0 ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">No rides</td></tr> :
                  d.rides.map((r: any) => (
                    <tr key={r._id}>
                      <td className="px-4 py-3 whitespace-nowrap">{new Date(r.createdAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                      <td className="px-4 py-3">{r.riderName || '—'}</td>
                      <td className="px-4 py-3">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 max-w-[300px] truncate">{r.pickupAddress} → {r.dropAddress}</td>
                      <td className="px-4 py-3 capitalize">{(r.service || 'taxi').replace('_', ' ')} · {r.vehicleType}</td>
                      <td className="px-4 py-3 capitalize">{r.paymentMode}</td>
                      <td className="px-4 py-3">{rupee(r.totalFare)}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
          {d && d.pages > 1 && (
            <div className="p-4 flex items-center justify-end gap-2 text-[13px]">
              <button type="button" disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Prev</button>
              <span>Page {d.page} of {d.pages}</span>
              <button type="button" disabled={page >= d.pages} onClick={() => setPage(p => p + 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Next</button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
