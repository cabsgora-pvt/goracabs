'use client'
import { useCallback, useEffect, useState } from 'react'
import { SlidersHorizontal, HandCoins, History } from 'lucide-react'
import { ZONE_FEATURES } from '@/lib/zone-features'

// Sections of the super admin's zone admin profile: what they may do, their
// revenue share, and the activity log.

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'
const card = 'bg-white rounded p-5 shadow-sm'
const rupee = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`

type Call = (url: string, method: string, body?: any, ok?: string) => Promise<boolean>

export function FeaturesCard({ a, call, busy }: { a: any; call: Call; busy: boolean }) {
  const [features, setFeatures] = useState<string[]>(a.features || [])
  const [share, setShare] = useState(String(a.revenueSharePercent ?? 0))
  const [limit, setLimit] = useState(String(a.priceChangeLimitPct ?? 30))
  useEffect(() => { setFeatures(a.features || []); setShare(String(a.revenueSharePercent ?? 0)); setLimit(String(a.priceChangeLimitPct ?? 30)) }, [a])

  return (
    <div className={card}>
      <h5 className="font-semibold text-[15px] mb-3 flex items-center gap-2"><SlidersHorizontal className="w-4 h-4" /> Permissions &amp; limits</h5>
      <div className="grid sm:grid-cols-2 gap-2">
        {ZONE_FEATURES.map(f => (
          <label key={f.key} className="flex items-center gap-2 text-[13px] border rounded px-3 py-2">
            <input type="checkbox" checked={features.includes(f.key)}
              onChange={e => setFeatures(e.target.checked ? [...features, f.key] : features.filter(x => x !== f.key))} />
            {f.label}
          </label>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-3 mt-4">
        <label className="text-[13px] text-[#495057]">Revenue share % of commission
          <input type="number" min={0} max={100} step="0.5" className={input} value={share} onChange={e => setShare(e.target.value)} />
        </label>
        <label className="text-[13px] text-[#495057]">Fare change limit ± % (0 = no limit)
          <input type="number" min={0} max={1000} className={input} value={limit} onChange={e => setLimit(e.target.value)} />
        </label>
      </div>
      <p className="text-xs text-gray-500 mt-2">Permissions come from the plan at each renewal; changes here apply now. Revenue share is for your records — payouts are made by you and recorded below.</p>
      <button type="button" disabled={busy}
        onClick={() => call(`/api/zone-admins/${a._id}`, 'PUT', { features, revenueSharePercent: Number(share), priceChangeLimitPct: Number(limit) }, 'Permissions saved')}
        className="mt-3 px-4 py-2 rounded bg-primary text-white text-[13px] font-medium">Save permissions</button>
    </div>
  )
}

export function RevenueShareCard({ a, call, busy }: { a: any; call: Call; busy: boolean }) {
  const [rows, setRows] = useState<any[] | null>(null)
  const [pay, setPay] = useState({ month: '', amount: '', paymentRef: '' })
  const load = useCallback(() => {
    fetch(`/api/zone-admins/${a._id}/settlement`).then(r => r.json()).then(d => {
      setRows(d.months || [])
      setPay(p => ({ ...p, month: p.month || d.months?.[1]?.month || d.months?.[0]?.month || '' }))
    }).catch(() => setRows([]))
  }, [a._id])
  useEffect(() => { load() }, [load, a.payouts?.length])

  return (
    <div className={card}>
      <h5 className="font-semibold text-[15px] mb-1 flex items-center gap-2"><HandCoins className="w-4 h-4" /> Revenue share ({a.revenueSharePercent || 0}%)</h5>
      <p className="text-[12.5px] text-gray-500 mb-3">Their share of the commission on rides completed in their zones.</p>
      <div className="overflow-x-auto">
        <table className="w-full text-[12.5px]">
          <thead><tr>{['Month', 'Rides', 'Commission', 'Share', 'Paid', 'Due'].map(h => <th key={h} className="text-left px-2 py-2">{h}</th>)}</tr></thead>
          <tbody className="divide-y">
            {!rows ? <tr><td colSpan={6} className="py-4 text-center text-gray-400">Loading…</td></tr> : rows.map(r => (
              <tr key={r.month}>
                <td className="px-2 py-2">{r.month}</td><td className="px-2 py-2">{r.rides}</td>
                <td className="px-2 py-2">{rupee(r.commission)}</td><td className="px-2 py-2">{rupee(r.share)}</td>
                <td className="px-2 py-2">{rupee(r.paid)}</td>
                <td className={`px-2 py-2 font-semibold ${r.due > 0 ? 'text-red-600' : 'text-green-600'}`}>{rupee(r.due)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="grid grid-cols-3 gap-2 mt-4">
        <label className="text-[12.5px] text-[#495057]">Month
          <select className={input} value={pay.month} onChange={e => setPay({ ...pay, month: e.target.value })}>
            {(rows || []).map(r => <option key={r.month} value={r.month}>{r.month}</option>)}
          </select>
        </label>
        <label className="text-[12.5px] text-[#495057]">Amount paid ₹<input type="number" min={0} className={input} value={pay.amount} onChange={e => setPay({ ...pay, amount: e.target.value })} /></label>
        <label className="text-[12.5px] text-[#495057]">Ref<input className={input} placeholder="UPI / bank" value={pay.paymentRef} onChange={e => setPay({ ...pay, paymentRef: e.target.value })} /></label>
      </div>
      <button type="button" disabled={busy || !pay.amount || !pay.month}
        onClick={async () => { if (await call(`/api/zone-admins/${a._id}/payouts`, 'POST', { ...pay, amount: Number(pay.amount) }, 'Payout recorded')) { setPay({ ...pay, amount: '', paymentRef: '' }); load() } }}
        className="mt-3 px-4 py-2 rounded bg-primary text-white text-[13px] font-medium disabled:opacity-50">Record payout</button>
    </div>
  )
}

const ACTION_LABEL: Record<string, string> = {
  'login': 'Signed in', 'pricing.update': 'Changed fares', 'driver.approve': 'Approved a driver', 'driver.reject': 'Rejected a driver',
  'driver.block': 'Blocked a driver', 'driver.unblock': 'Unblocked a driver', 'promo.create': 'Created a promo code',
  'promo.on': 'Turned a promo on', 'promo.off': 'Turned a promo off', 'promo.delete': 'Deleted a promo code',
  'staff.create': 'Added staff', 'staff.update': 'Updated staff', 'staff.delete': 'Removed staff',
  'ticket.update': 'Updated a support ticket', 'sos.resolved': 'Resolved an SOS', 'sos.active': 'Reopened an SOS',
  'zone.support_phone': 'Changed zone helpline', 'password.changed': 'Changed password', 'password.reset_requested': 'Asked for a password reset',
  'admin.update': 'Super admin updated the account', 'admin.view_as': 'Super admin opened their panel',
  'subscription.renew': 'Plan assigned / renewed', 'payout.record': 'Revenue share payout recorded',
}

export function ActivityCard({ id }: { id: string }) {
  const [d, setD] = useState<any>(null)
  const [page, setPage] = useState(1)
  useEffect(() => { fetch(`/api/zone-admins/${id}/activity?page=${page}`).then(r => r.json()).then(setD).catch(() => {}) }, [id, page])

  const detail = (x: any) => {
    const v = x.details
    if (!v) return ''
    if (x.action === 'pricing.update' && v.changes) {
      return `${v.zone} · ${v.vehicle} ${v.service}: ` + Object.entries(v.changes).map(([k, c]: any) => `${k} ${c.from}→${c.to}`).join(', ')
    }
    return Object.entries(v).filter(([, val]) => val !== undefined && val !== null && typeof val !== 'object').map(([k, val]) => `${k}: ${val}`).join(' · ')
  }

  return (
    <div className={card}>
      <h5 className="font-semibold text-[15px] mb-3 flex items-center gap-2"><History className="w-4 h-4" /> Activity log</h5>
      {!d ? <p className="text-gray-400 text-[13px]">Loading…</p> : d.items.length === 0 ? <p className="text-gray-400 text-[13px]">No activity yet</p> : (
        <div className="divide-y">
          {d.items.map((x: any) => (
            <div key={x._id} className="py-2.5 text-[12.5px]">
              <div className="flex justify-between gap-3">
                <span className="font-medium text-[#495057]">{ACTION_LABEL[x.action] || x.action}</span>
                <span className="text-gray-400 whitespace-nowrap">{new Date(x.createdAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</span>
              </div>
              <p className="text-gray-500">{x.actorName} <span className="text-gray-400">({x.actorType.replace('_', ' ')})</span>{detail(x) ? ` — ${detail(x)}` : ''}</p>
            </div>
          ))}
        </div>
      )}
      {d && d.pages > 1 && (
        <div className="flex justify-end gap-2 mt-3 text-[12.5px]">
          <button type="button" disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="px-3 py-1 border rounded disabled:opacity-40">Newer</button>
          <button type="button" disabled={page >= d.pages} onClick={() => setPage(p => p + 1)} className="px-3 py-1 border rounded disabled:opacity-40">Older</button>
        </div>
      )}
    </div>
  )
}
