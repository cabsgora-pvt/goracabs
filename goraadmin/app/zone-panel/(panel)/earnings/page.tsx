'use client'
import { useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { zoneFetch } from '@/components/zone-shell'
import { fmtDate } from '@/lib/zone-admin-ui'

const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

// The zone admin's revenue share: their % of Gora's commission in their zones.
export default function ZoneEarnings() {
  const [d, setD] = useState<any>(null)
  useEffect(() => { zoneFetch('/api/zone-admin/settlement').then(r => r.json()).then(setD).catch(() => {}) }, [])

  return (
    <div>
      <Header title="Earnings" />
      <div className="p-6 space-y-4">
        {!d ? <p className="text-gray-400">Loading…</p> : (
          <>
            <div className="bg-white rounded shadow-sm p-5 text-[13px] text-gray-600">
              {d.sharePercent > 0
                ? <>You earn <b className="text-[#495057]">{d.sharePercent}%</b> of Gora&apos;s commission on rides completed in your zones, and {d.sharePercent}% of every driver subscription bought in your zones (a driver on a subscription pays no commission on rides). Gora pays it to you and records it here.</>
                : <>Your plan has no revenue share. Contact Gora to discuss one.</>}
            </div>
            <div className="bg-white rounded shadow-sm overflow-x-auto">
              <table className="w-full text-[13px]">
                <thead><tr>{['Month', 'Completed rides', 'Ride revenue', 'Commission', 'Ride share', 'Driver subscriptions', 'Subscription share', 'Your total', 'Paid to you', 'Due'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
                <tbody className="divide-y">
                  {d.months.map((m: any) => (
                    <tr key={m.month}>
                      <td className="px-4 py-3">{m.month}</td><td className="px-4 py-3">{m.rides}</td><td className="px-4 py-3">{rupee(m.fare)}</td>
                      <td className="px-4 py-3">{rupee(m.commission)}</td><td className="px-4 py-3">{rupee(m.rideShare)}</td>
                      <td className="px-4 py-3">{m.subscriptions ? `${m.subscriptions} · ${rupee(m.subscriptionAmount)}` : '—'}</td>
                      <td className="px-4 py-3">{rupee(m.subscriptionShare)}</td>
                      <td className="px-4 py-3 font-semibold">{rupee(m.share)}</td>
                      <td className="px-4 py-3">{rupee(m.paid)}</td><td className={`px-4 py-3 font-semibold ${m.due > 0 ? 'text-yellow-700' : 'text-green-600'}`}>{rupee(m.due)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="bg-white rounded shadow-sm overflow-x-auto">
              <div className="px-5 py-4 border-b border-[#e9ebec]"><h5 className="font-semibold text-[15px]">Payouts received</h5></div>
              <table className="w-full text-[13px]">
                <thead><tr>{['Date', 'For month', 'Amount', 'Ref'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
                <tbody className="divide-y">
                  {d.payouts.length === 0 ? <tr><td colSpan={4} className="text-center py-6 text-gray-400">No payouts yet</td></tr> :
                    d.payouts.map((p: any) => (
                      <tr key={p._id}><td className="px-4 py-3">{fmtDate(p.createdAt)}</td><td className="px-4 py-3">{p.month}</td><td className="px-4 py-3">{rupee(p.amount)}</td><td className="px-4 py-3 text-gray-500">{p.paymentRef || '—'}</td></tr>
                    ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
