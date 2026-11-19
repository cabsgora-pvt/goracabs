'use client'
import { useCallback, useEffect, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import { ArrowLeft, Ban, CheckCircle2, KeyRound, Trash2, Wallet, Map as MapIcon, Car, Receipt, IndianRupee, LogIn, FileText } from 'lucide-react'
import { Header } from '@/components/header'
import { FranchiseOffBanner } from '@/components/franchise-mode'
import { Toast } from '@/components/ui/toast'
import { ACCESS_LABEL, daysLeft, fmtDate } from '@/lib/zone-admin-ui'
import { ActivityCard, FeaturesCard, RevenueShareCard } from '@/components/zone-admin-extras'

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'
const card = 'bg-white rounded p-5 shadow-sm'

export default function ZoneAdminProfilePage() {
  const { id } = useParams<{ id: string }>()
  const router = useRouter()
  const [a, setA] = useState<any>(null)
  const [stats, setStats] = useState<any>(null)
  const [zones, setZones] = useState<{ _id: string; name: string }[]>([])
  const [others, setOthers] = useState<Map<string, string>>(new Map())
  const [plans, setPlans] = useState<{ _id: string; name: string; months: number; price: number; isActive: boolean }[]>([])
  const [pay, setPay] = useState({ planId: '', paymentRef: '' })
  const [zoneSel, setZoneSel] = useState<string[]>([])
  const [newPass, setNewPass] = useState('')
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(async () => {
    const [d, z, all, pl] = await Promise.all([
      fetch(`/api/zone-admins/${id}`).then(r => r.json()),
      fetch('/api/zones').then(r => r.json()),
      fetch('/api/zone-admins').then(r => r.json()),
      fetch('/api/zone-plans').then(r => r.json()),
    ])
    setPlans((pl.plans || []).filter((p: any) => p.isActive))
    if (d.zoneAdmin) { setA(d.zoneAdmin); setStats(d.stats); setZoneSel(d.zoneAdmin.zoneIds) }
    setZones(z.zones || [])
    const m = new Map<string, string>()
    for (const o of all.zoneAdmins || []) if (o._id !== id) for (const zz of o.zones) m.set(zz._id, o.name)
    setOthers(m)
  }, [id])
  useEffect(() => { load() }, [load])

  const call = async (url: string, method: string, body?: any, ok = 'Saved') => {
    setBusy(true)
    try {
      const res = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined })
      const d = await res.json()
      if (!res.ok) { setToast({ msg: d.error || 'Failed', type: 'error' }); return false }
      if (d.zoneAdmin) { setA(d.zoneAdmin); setZoneSel(d.zoneAdmin.zoneIds) }
      setToast({ msg: ok, type: 'success' })
      return true
    } finally { setBusy(false) }
  }

  if (!a) return <div><Header title="Zone Admin" /><div className="p-6 text-gray-400">Loading…</div></div>

  const st = ACCESS_LABEL[a.access] || ACCESS_LABEL.active
  const left = daysLeft(a.subscriptionEndAt)

  return (
    <div>
      <Header title="Zone Admin Profile" />
      <div className="p-6 space-y-5">
        <FranchiseOffBanner />
        <Link href="/zone-admins" className="inline-flex items-center gap-1 text-[13px] text-primary"><ArrowLeft className="w-4 h-4" /> All zone admins</Link>

        {/* Profile header */}
        <div className={`${card} flex flex-wrap items-center gap-5`}>
          <div className="w-16 h-16 rounded-full bg-primary text-white flex items-center justify-center text-2xl font-semibold">
            {a.name?.[0]?.toUpperCase()}
          </div>
          <div className="flex-1 min-w-[200px]">
            <h3 className="text-[18px] font-semibold text-[#495057]">{a.name}</h3>
            <p className="text-[13px] text-gray-500">{a.businessName || '—'} · {a.email}{a.phone ? ` · ${a.phone}` : ''}</p>
            <p className="text-[12px] text-gray-400 mt-1">Joined {fmtDate(a.createdAt)} · Last login {a.lastLoginAt ? fmtDate(a.lastLoginAt) : 'never'}</p>
          </div>
          <span className={`inline-flex px-2.5 py-1 rounded text-[11px] font-semibold uppercase ${st.cls}`}>{st.text}</span>
          <button type="button" disabled={busy} title="Open their zone panel in a new tab, as them, for 2 hours (logged)"
            onClick={async () => { if (await call(`/api/zone-admins/${id}/impersonate`, 'POST', undefined, 'Opening their panel…')) window.open('/zone-panel', '_blank') }}
            className="inline-flex items-center gap-1 px-3 py-2 rounded border border-primary text-primary text-[13px]"><LogIn className="w-4 h-4" /> Login as zone admin</button>
          {a.status === 'blocked' ? (
            <button type="button" disabled={busy} onClick={() => call(`/api/zone-admins/${id}`, 'PUT', { status: 'active' }, 'Unblocked')}
              className="inline-flex items-center gap-1 px-3 py-2 rounded bg-green-600 text-white text-[13px]"><CheckCircle2 className="w-4 h-4" /> Unblock</button>
          ) : (
            <button type="button" disabled={busy} onClick={() => call(`/api/zone-admins/${id}`, 'PUT', { status: 'blocked' }, 'Blocked')}
              className="inline-flex items-center gap-1 px-3 py-2 rounded bg-red-500 text-white text-[13px]"><Ban className="w-4 h-4" /> Block</button>
          )}
        </div>

        {a.passwordResetRequestedAt && (
          <div className="bg-sky-50 border border-sky-200 text-sky-800 rounded px-4 py-3 text-[13px]">
            Asked for a password reset on {fmtDate(a.passwordResetRequestedAt)}. Set a new one under “Reset password” and share it with them.
          </div>
        )}

        {/* Stats of their zones */}
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {[
            { label: 'Zones', value: a.zones.length, icon: MapIcon },
            { label: 'Drivers in zones', value: stats?.drivers ?? 0, icon: Car },
            { label: 'Completed rides', value: stats?.completedRides ?? 0, icon: Receipt },
            { label: 'Ride revenue', value: `₹${Math.round(stats?.revenue || 0).toLocaleString('en-IN')}`, icon: IndianRupee },
          ].map(s => (
            <div key={s.label} className={`${card} flex items-center justify-between`}>
              <div>
                <p className="text-[13px] uppercase text-[#878a99] font-medium">{s.label}</p>
                <p className="text-[22px] font-semibold text-[#495057] mt-2">{s.value}</p>
              </div>
              <div className="w-12 h-12 rounded bg-blue-50 flex items-center justify-center"><s.icon className="w-6 h-6 text-blue-600" /></div>
            </div>
          ))}
        </div>

        <div className="grid lg:grid-cols-2 gap-5">
          {/* Subscription */}
          <div className={card}>
            <h5 className="font-semibold text-[15px] mb-1 flex items-center gap-2"><Wallet className="w-4 h-4" /> Subscription</h5>
            <p className="text-[13px] text-gray-600 mb-4">
              {a.subscriptionEndAt
                ? <>Valid till <b>{fmtDate(a.subscriptionEndAt)}</b>{left !== null && (left > 0 ? ` · ${left} day${left === 1 ? '' : 's'} left` : ' · expired')}</>
                : 'No subscription yet — the zone admin cannot sign in.'}
              <span className="block text-gray-500 mt-1">Total received: ₹{Math.round(a.totalPaid).toLocaleString('en-IN')}</span>
            </p>
            {plans.length === 0 ? (
              <p className="text-[13px] text-gray-500">No active plans — add one under <a href="/zone-plans" className="text-primary underline">Subscription Plans</a>.</p>
            ) : (
              <div className="grid grid-cols-2 gap-3">
                <label className="text-[13px] text-[#495057]">Plan
                  <select className={input} value={pay.planId} onChange={e => setPay({ ...pay, planId: e.target.value })}>
                    <option value="">Choose a plan</option>
                    {plans.map(p => <option key={p._id} value={p._id}>{p.name} — {p.months} mo — ₹{p.price.toLocaleString('en-IN')}</option>)}
                  </select>
                </label>
                <label className="text-[13px] text-[#495057]">Payment ref<input className={input} placeholder="UPI / bank ref" value={pay.paymentRef} onChange={e => setPay({ ...pay, paymentRef: e.target.value })} /></label>
              </div>
            )}
            <button type="button" disabled={busy || !pay.planId}
              onClick={async () => { if (await call(`/api/zone-admins/${id}/subscription`, 'POST', pay, 'Plan assigned, access extended')) setPay({ planId: '', paymentRef: '' }) }}
              className="mt-4 px-4 py-2 rounded bg-primary text-white text-[13px] font-medium disabled:opacity-50">
              {a.subscriptionEndAt ? 'Renew with plan' : 'Assign plan'}
            </button>

            <div className="mt-5 border-t pt-4">
              <p className="text-[13px] font-semibold text-[#495057] mb-2">Payment history</p>
              {a.payments.length === 0 ? <p className="text-[13px] text-gray-400">No payments yet</p> : (
                <table className="w-full text-[12.5px]">
                  <thead><tr>{['Date', 'Plan', 'Period', 'Amount', 'Ref', ''].map(h => <th key={h} className="text-left px-2 py-2">{h}</th>)}</tr></thead>
                  <tbody className="divide-y">
                    {a.payments.map((p: any) => (
                      <tr key={p._id}>
                        <td className="px-2 py-2">{fmtDate(p.createdAt)}</td>
                        <td className="px-2 py-2">{p.planName}</td>
                        <td className="px-2 py-2">{fmtDate(p.periodStart)} – {fmtDate(p.periodEnd)}</td>
                        <td className="px-2 py-2">₹{Math.round(p.amount).toLocaleString('en-IN')}</td>
                        <td className="px-2 py-2 text-gray-500">{p.paymentRef || '—'}</td>
                        <td className="px-2 py-2"><a href={`/zone-invoice/${id}/${p._id}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-primary"><FileText className="w-3.5 h-3.5" />{p.invoiceNo || 'Invoice'}</a></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </div>

          <div className="space-y-5">
            {/* Zones */}
            <div className={card}>
              <h5 className="font-semibold text-[15px] mb-3 flex items-center gap-2"><MapIcon className="w-4 h-4" /> Assigned zones</h5>
              <div className="grid sm:grid-cols-2 gap-2">
                {zones.map(z => {
                  const holder = others.get(z._id)
                  return (
                    <label key={z._id} className={`flex items-center gap-2 border rounded px-3 py-2 text-[13px] ${holder ? 'opacity-50' : ''}`}>
                      <input type="checkbox" disabled={!!holder} checked={zoneSel.includes(z._id)}
                        onChange={e => setZoneSel(e.target.checked ? [...zoneSel, z._id] : zoneSel.filter(x => x !== z._id))} />
                      <span className="flex-1">{z.name}</span>
                      {holder && <span className="text-[11px] text-gray-500">{holder}</span>}
                    </label>
                  )
                })}
              </div>
              <button type="button" disabled={busy} onClick={() => call(`/api/zone-admins/${id}`, 'PUT', { zoneIds: zoneSel }, 'Zones updated')}
                className="mt-3 px-4 py-2 rounded bg-primary text-white text-[13px] font-medium">Save zones</button>
            </div>

            {/* Login */}
            <div className={card}>
              <h5 className="font-semibold text-[15px] mb-3 flex items-center gap-2"><KeyRound className="w-4 h-4" /> Reset password</h5>
              <div className="flex gap-2">
                <input className={input} placeholder="New password (min 8)" value={newPass} onChange={e => setNewPass(e.target.value)} />
                <button type="button" disabled={busy || newPass.length < 8}
                  onClick={async () => { if (await call(`/api/zone-admins/${id}`, 'PUT', { password: newPass }, 'Password changed')) setNewPass('') }}
                  className="px-4 py-2 rounded bg-primary text-white text-[13px] whitespace-nowrap disabled:opacity-50">Set</button>
              </div>
              <p className="text-xs text-gray-500 mt-2">Zone panel login: /zone-panel/login with {a.email}</p>
            </div>

            <button type="button" disabled={busy}
              onClick={async () => { if (confirm(`Delete zone admin ${a.name}? Their zones become unassigned.`) && await call(`/api/zone-admins/${id}`, 'DELETE', undefined, 'Deleted')) router.push('/zone-admins') }}
              className="inline-flex items-center gap-1 text-[13px] text-red-600"><Trash2 className="w-4 h-4" /> Delete zone admin</button>
          </div>
        </div>
        <div className="grid lg:grid-cols-2 gap-5">
          <FeaturesCard a={a} call={call} busy={busy} />
          <RevenueShareCard a={a} call={call} busy={busy} />
        </div>
        <ActivityCard id={id} />
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
