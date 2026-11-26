'use client'
import { useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { zoneFetch } from '@/components/zone-shell'

const STATUSES = ['', 'pending', 'accepted', 'ongoing', 'completed', 'cancelled']
const SERVICES = [['', 'All services'], ['taxi', 'Taxi'], ['delivery', 'Parcel'], ['rental', 'Rental'], ['outstation', 'Outstation'], ['hire_driver', 'Hire driver']]
const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

export default function ZoneRides() {
  const [status, setStatus] = useState('')
  const [service, setService] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [q, setQ] = useState('')
  const [appliedQ, setAppliedQ] = useState('')
  const [page, setPage] = useState(1)
  const [d, setD] = useState<any>(null)

  useEffect(() => {
    setD(null)
    const p = new URLSearchParams({ page: String(page) })
    if (status) p.set('status', status)
    if (service) p.set('service', service)
    if (from) p.set('from', from)
    if (to) p.set('to', to)
    if (appliedQ) p.set('q', appliedQ)
    zoneFetch(`/api/zone-admin/rides?${p}`).then(r => r.json()).then(setD).catch(() => {})
  }, [status, service, from, to, appliedQ, page])

  const inp = 'border border-[#e9ebec] rounded px-3 py-1.5 text-[13px] bg-white'

  return (
    <div>
      <Header title="Rides" />
      <div className="p-6">
        <div className="bg-white rounded shadow-sm">
          <div className="p-4 border-b border-[#e9ebec] flex flex-wrap gap-2 items-center">
            {STATUSES.map(s => (
              <button key={s || 'all'} type="button" onClick={() => { setStatus(s); setPage(1) }}
                className={`px-3 py-1.5 rounded text-[13px] capitalize ${status === s ? 'bg-primary text-white' : 'bg-[#f3f6f9] text-[#495057]'}`}>
                {s || 'All'}
              </button>
            ))}
          </div>
          <div className="p-4 border-b border-[#e9ebec] flex flex-wrap gap-3 items-end">
            <select aria-label="Service" className={inp} value={service} onChange={e => { setService(e.target.value); setPage(1) }}>
              {SERVICES.map(([v, l]) => <option key={v || 'all'} value={v}>{l}</option>)}
            </select>
            <label className="text-[12px] text-gray-500">From
              <input type="date" aria-label="From date" className={`${inp} block`} value={from} onChange={e => { setFrom(e.target.value); setPage(1) }} />
            </label>
            <label className="text-[12px] text-gray-500">To
              <input type="date" aria-label="To date" className={`${inp} block`} value={to} onChange={e => { setTo(e.target.value); setPage(1) }} />
            </label>
            <input aria-label="Search rides" className={`${inp} flex-1 min-w-[200px]`} value={q} onChange={e => setQ(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter') { setAppliedQ(q.trim()); setPage(1) } }}
              onBlur={() => { if (q.trim() !== appliedQ) { setAppliedQ(q.trim()); setPage(1) } }}
              placeholder="Rider / driver name or phone, address, ride id (Enter)" />
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-[13px]">
              <thead><tr>{['Date', 'Rider', 'Driver', 'Route', 'Service', 'Payment', 'Fare', 'Status'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {!d ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">Loading…</td></tr> :
                  !d.rides?.length ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">{d.error || 'No rides'}</td></tr> :
                  d.rides.map((r: any) => (
                    <tr key={r._id}>
                      <td className="px-4 py-3 whitespace-nowrap">{new Date(r.createdAt).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
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
          {d && !d.error && (
            <div className="p-4 flex items-center justify-between gap-2 text-[13px]">
              <span className="text-gray-500">{d.total} ride{d.total === 1 ? '' : 's'}</span>
              <div className="flex items-center gap-2">
                <button type="button" disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Prev</button>
                <span>Page {d.page} of {d.pages}</span>
                <button type="button" disabled={page >= d.pages} onClick={() => setPage(p => p + 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Next</button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
