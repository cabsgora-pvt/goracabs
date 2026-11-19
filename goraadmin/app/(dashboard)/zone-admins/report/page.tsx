'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { FranchiseOffBanner } from '@/components/franchise-mode'
import { PageHeader } from '@/components/ui/page-header'
import { ACCESS_LABEL, fmtDate } from '@/lib/zone-admin-ui'

const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`
const card = 'bg-white rounded shadow-sm'

// The franchise business at a glance for the super admin.
export default function FranchiseReportPage() {
  const [month, setMonth] = useState('')
  const [d, setD] = useState<any>(null)
  useEffect(() => {
    setD(null)
    fetch(`/api/zone-admins/report${month ? `?month=${month}` : ''}`).then(r => r.json()).then(x => { setD(x); if (!month) setMonth(x.month) }).catch(() => {})
  }, [month])

  return (
    <div>
      <Header title="Franchise Report" />
      <div className="p-6 space-y-5">
        <FranchiseOffBanner />
        <PageHeader title="Franchise Report" subtitle="Subscriptions, renewals and revenue share across all zone admins"
          action={<input type="month" value={month} onChange={e => setMonth(e.target.value)} className="border border-[#ced4da] rounded px-3 py-2 text-[13px]" />} />
        {!d ? <p className="text-gray-400">Loading…</p> : (
          <>
            <div className="grid sm:grid-cols-2 xl:grid-cols-4 gap-4">
              {[
                { l: 'Zone admins', v: d.totals.zoneAdmins },
                { l: `Subscription income (${d.month})`, v: rupee(d.totals.subscriptionIncomeThisMonth) },
                { l: 'Subscription income (all time)', v: rupee(d.totals.subscriptionIncomeAllTime) },
                { l: `Revenue share still due (${d.month})`, v: rupee(d.totals.shareOwed) },
              ].map(c => (
                <div key={c.l} className={`${card} p-4`}>
                  <p className="text-[12px] uppercase font-medium text-[#878a99]">{c.l}</p>
                  <p className="text-[22px] font-semibold text-[#495057] mt-1">{c.v}</p>
                </div>
              ))}
            </div>

            <div className={card}>
              <div className="px-5 py-4 border-b border-[#e9ebec]"><h5 className="font-semibold text-[15px]">Renewals due in the next 30 days</h5></div>
              <table className="w-full text-[13px]">
                <thead><tr>{['Zone admin', 'Zones', 'Ends', 'Days left'].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
                <tbody className="divide-y">
                  {d.expiringSoon.length === 0 ? <tr><td colSpan={4} className="text-center py-6 text-gray-400">None</td></tr> :
                    d.expiringSoon.map((r: any) => (
                      <tr key={r._id}>
                        <td className="px-4 py-3"><Link href={`/zone-admins/${r._id}`} className="text-primary font-medium">{r.name}</Link></td>
                        <td className="px-4 py-3">{r.zones.join(', ')}</td>
                        <td className="px-4 py-3">{fmtDate(r.subscriptionEndAt)}</td>
                        <td className={`px-4 py-3 font-semibold ${r.daysLeft <= 7 ? 'text-red-600' : 'text-yellow-600'}`}>{r.daysLeft}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>

            <div className={card}>
              <div className="px-5 py-4 border-b border-[#e9ebec]"><h5 className="font-semibold text-[15px]">All zone admins — {d.month}</h5></div>
              <div className="overflow-x-auto">
                <table className="w-full text-[13px]">
                  <thead><tr>{['Zone admin', 'Zones', 'Status', 'Subscription paid', 'Rides', 'Commission', 'Share %', 'Share due', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
                  <tbody className="divide-y">
                    {d.rows.map((r: any) => {
                      const st = ACCESS_LABEL[r.access] || ACCESS_LABEL.active
                      return (
                        <tr key={r._id}>
                          <td className="px-4 py-3"><Link href={`/zone-admins/${r._id}`} className="text-primary font-medium">{r.name}</Link></td>
                          <td className="px-4 py-3">{r.zones.join(', ') || '—'}</td>
                          <td className="px-4 py-3"><span className={`px-2 py-[3px] rounded text-[10.5px] font-semibold uppercase ${st.cls}`}>{st.text}</span></td>
                          <td className="px-4 py-3">{rupee(r.totalPaid)}</td>
                          <td className="px-4 py-3">{r.settlement.rides}</td>
                          <td className="px-4 py-3">{rupee(r.settlement.commission)}</td>
                          <td className="px-4 py-3">{r.settlement.sharePercent}%</td>
                          <td className={`px-4 py-3 font-semibold ${r.settlement.due > 0 ? 'text-red-600' : ''}`}>{rupee(r.settlement.due)}</td>
                          <td className="px-4 py-3 text-sky-700 text-[12px]">{r.passwordResetRequested ? 'Reset requested' : ''}</td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
