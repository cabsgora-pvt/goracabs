'use client'
import { useEffect, useState } from 'react'
import { Download } from 'lucide-react'
import { Header } from '@/components/header'
import { zoneFetch } from '@/components/zone-shell'

const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`
const istToday = () => new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10)
const istDaysAgo = (n: number) => new Date(Date.now() + 5.5 * 3600e3 - n * 864e5).toISOString().slice(0, 10)

export default function ZoneReports() {
  const [from, setFrom] = useState(istDaysAgo(29))
  const [to, setTo] = useState(istToday())
  const [d, setD] = useState<any>(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    setD(null); setErr('')
    zoneFetch(`/api/zone-admin/reports?from=${from}&to=${to}`).then(async r => {
      const x = await r.json(); if (!r.ok) setErr(x.error || 'Could not load'); else setD(x)
    }).catch(() => {})
  }, [from, to])

  return (
    <div>
      <Header title="Reports" />
      <div className="p-6 space-y-4">
        <div className="bg-white rounded shadow-sm p-4 flex flex-wrap items-end gap-3">
          <label className="text-[13px]">From<input type="date" value={from} max={to} onChange={e => setFrom(e.target.value)} className="block border border-[#ced4da] rounded px-3 py-2" /></label>
          <label className="text-[13px]">To<input type="date" value={to} min={from} max={istToday()} onChange={e => setTo(e.target.value)} className="block border border-[#ced4da] rounded px-3 py-2" /></label>
          <a href={`/api/zone-admin/reports?from=${from}&to=${to}&format=csv`}
            className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px] ml-auto"><Download className="w-4 h-4" /> Download rides (Excel / CSV)</a>
        </div>
        {err && <p className="text-red-600 text-[13px]">{err}</p>}
        {d && (
          <div className="grid sm:grid-cols-2 xl:grid-cols-5 gap-4">
            {[
              ['Rides', d.totals.rides], ['Completed', d.totals.completed], ['Cancelled', d.totals.cancelled],
              ['Revenue', rupee(d.totals.revenue)], ['Commission to Gora', rupee(d.totals.commission)],
            ].map(([l, v]) => (
              <div key={l as string} className="bg-white rounded shadow-sm p-4">
                <p className="text-[12px] uppercase font-medium text-[#878a99]">{l}</p>
                <p className="text-[20px] font-semibold text-[#495057] mt-1">{v}</p>
              </div>
            ))}
          </div>
        )}
        <div className="bg-white rounded shadow-sm overflow-x-auto">
          <table className="w-full text-[13px]">
            <thead><tr>{['Day', 'Rides', 'Completed', 'Cancelled', 'Revenue', 'Commission'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
            <tbody className="divide-y">
              {!d ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">{err ? '' : 'Loading…'}</td></tr> : d.days.length === 0 ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">No rides in these dates</td></tr> :
                d.days.map((x: any) => (
                  <tr key={x._id}>
                    <td className="px-4 py-3">{x._id}</td><td className="px-4 py-3">{x.rides}</td><td className="px-4 py-3">{x.completed}</td>
                    <td className="px-4 py-3">{x.cancelled}</td><td className="px-4 py-3">{rupee(x.revenue)}</td><td className="px-4 py-3">{rupee(x.commission)}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
