'use client'
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Plus, Eye, Search, KeyRound, BarChart3 } from 'lucide-react'
import { Header } from '@/components/header'
import { FranchiseOffBanner } from '@/components/franchise-mode'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { ACCESS_LABEL, fmtDate } from '@/lib/zone-admin-ui'

type ZoneAdminRow = {
  _id: string; name: string; email: string; phone?: string; businessName?: string
  zones: { _id: string; name: string }[]; status: string; access: string
  subscriptionEndAt: string | null; totalPaid: number; passwordResetRequestedAt?: string | null
}
type ZoneOpt = { _id: string; name: string; city?: string }
type PlanOpt = { _id: string; name: string; months: number; price: number; isActive: boolean }

const emptyForm = {
  name: '', email: '', phone: '', password: '', businessName: '', address: '', gstNumber: '',
  zoneIds: [] as string[], planId: '', paymentRef: '',
}

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'

export default function ZoneAdminsPage() {
  const [rows, setRows] = useState<ZoneAdminRow[]>([])
  const [zones, setZones] = useState<ZoneOpt[]>([])
  const [plans, setPlans] = useState<PlanOpt[]>([])
  const [loading, setLoading] = useState(true)
  const [summary, setSummary] = useState<any>(null)
  const [q, setQ] = useState('')
  const [showAdd, setShowAdd] = useState(false)
  const [form, setForm] = useState(emptyForm)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [a, z, p] = await Promise.all([
        fetch('/api/zone-admins').then(r => r.json()), fetch('/api/zones').then(r => r.json()), fetch('/api/zone-plans').then(r => r.json()),
      ])
      setRows(a.zoneAdmins || [])
      setZones(z.zones || [])
      setPlans((p.plans || []).filter((x: PlanOpt) => x.isActive))
      fetch('/api/zone-admins/report').then(r => r.json()).then(setSummary).catch(() => {})
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { load() }, [load])

  // A zone already run by someone cannot be picked again.
  const takenBy = new Map<string, string>()
  rows.forEach(r => r.zones.forEach(z => takenBy.set(z._id, r.name)))

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await fetch('/api/zone-admins', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: form.name, email: form.email, phone: form.phone, password: form.password,
          businessName: form.businessName, address: form.address, gstNumber: form.gstNumber, zoneIds: form.zoneIds,
          planId: form.planId || undefined, paymentRef: form.paymentRef,
        }),
      })
      const d = await res.json()
      if (!res.ok) { setToast({ msg: d.error || 'Could not create', type: 'error' }); return }
      setToast({ msg: 'Zone admin created', type: 'success' })
      setShowAdd(false); setForm(emptyForm); load()
    } finally { setSaving(false) }
  }

  const shown = rows.filter(r => !q || [r.name, r.email, r.phone, r.businessName, ...r.zones.map(z => z.name)]
    .some(v => (v || '').toLowerCase().includes(q.toLowerCase())))

  return (
    <div>
      <Header title="Zone Admins" />
      <div className="p-6 space-y-5">
        <FranchiseOffBanner />
        <PageHeader
          title="Zone Admins (Franchise)"
          subtitle="Each zone admin runs their zones on a paid subscription. Access stops when it expires."
          action={
            <button type="button" onClick={() => setShowAdd(true)}
              className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px] font-medium">
              <Plus className="w-4 h-4" /> Add Zone Admin
            </button>
          }
        />

        {summary?.totals && (
          <div className="grid sm:grid-cols-2 xl:grid-cols-5 gap-4">
            {[
              { label: 'Active', value: summary.totals.active || 0, cls: 'text-green-600' },
              { label: 'Expiring in 7 days', value: (summary.expiringSoon || []).filter((r: any) => r.daysLeft <= 7).length, cls: 'text-yellow-600' },
              { label: 'Grace / expired', value: (summary.totals.grace || 0) + (summary.totals.expired || 0), cls: 'text-red-600' },
              { label: 'Password reset requests', value: summary.totals.resetRequests || 0, cls: 'text-sky-600' },
              { label: 'Subscription income (all time)', value: `₹${Math.round(summary.totals.subscriptionIncomeAllTime || 0).toLocaleString('en-IN')}`, cls: 'text-primary' },
            ].map(c => (
              <div key={c.label} className="bg-white rounded shadow-sm p-4">
                <p className="text-[12px] uppercase font-medium text-[#878a99]">{c.label}</p>
                <p className={`text-[22px] font-semibold mt-1 ${c.cls}`}>{c.value}</p>
              </div>
            ))}
          </div>
        )}
        <div className="flex justify-end">
          <Link href="/zone-admins/report" className="inline-flex items-center gap-1 text-[13px] text-primary font-medium"><BarChart3 className="w-4 h-4" /> Franchise report</Link>
        </div>

        <div className="bg-white rounded shadow-sm">
          <div className="p-4 border-b border-[#e9ebec]">
            <div className="flex items-center gap-2 border border-[#ced4da] rounded px-3 py-2 max-w-sm">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={q} onChange={e => setQ(e.target.value)} placeholder="Search name, email or zone…"
                className="outline-none text-[13px] w-full" />
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-[13px]">
              <thead>
                <tr>
                  {['Zone Admin', 'Zones', 'Subscription ends', 'Total paid', 'Status', ''].map(h => (
                    <th key={h} className="text-left px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y">
                {loading ? (
                  <tr><td colSpan={6} className="text-center py-10 text-gray-400">Loading…</td></tr>
                ) : shown.length === 0 ? (
                  <tr><td colSpan={6} className="text-center py-10 text-gray-400">No zone admins yet</td></tr>
                ) : shown.map(r => {
                  const st = ACCESS_LABEL[r.access] || ACCESS_LABEL.active
                  return (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3">
                        <p className="font-semibold text-[#495057] flex items-center gap-1.5">{r.name}
                          {r.passwordResetRequestedAt && <span title="Asked for a password reset" className="inline-flex items-center gap-0.5 text-[10.5px] text-sky-700 bg-sky-50 px-1.5 py-0.5 rounded"><KeyRound className="w-3 h-3" />Reset</span>}
                        </p>
                        <p className="text-gray-500 text-xs">{r.email}{r.phone ? ` · ${r.phone}` : ''}</p>
                      </td>
                      <td className="px-4 py-3">{r.zones.map(z => z.name).join(', ') || <span className="text-gray-400">None</span>}</td>
                      <td className="px-4 py-3">{fmtDate(r.subscriptionEndAt)}</td>
                      <td className="px-4 py-3">₹{Math.round(r.totalPaid).toLocaleString('en-IN')}</td>
                      <td className="px-4 py-3">
                        <span className={`inline-flex px-2 py-[3px] rounded text-[10.5px] font-semibold uppercase ${st.cls}`}>{st.text}</span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <Link href={`/zone-admins/${r._id}`} className="inline-flex items-center gap-1 text-primary font-medium">
                          <Eye className="w-4 h-4" /> View
                        </Link>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {showAdd && (
        <Modal title="Add Zone Admin" onClose={() => setShowAdd(false)} size="lg">
          <form onSubmit={submit} className="space-y-4">
            <div className="grid sm:grid-cols-2 gap-3">
              <label className="text-[13px] text-[#495057]">Name *<input className={input} required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">Business name<input className={input} value={form.businessName} onChange={e => setForm({ ...form, businessName: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">Email (login) *<input type="email" className={input} required value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">Password * (min 8)<input type="text" className={input} required minLength={8} value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">Phone<input className={input} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">GST number<input className={input} value={form.gstNumber} onChange={e => setForm({ ...form, gstNumber: e.target.value })} /></label>
            </div>
            <label className="block text-[13px] text-[#495057]">Address<input className={input} value={form.address} onChange={e => setForm({ ...form, address: e.target.value })} /></label>

            <div>
              <p className="text-[13px] font-semibold text-[#495057] mb-2">Assign zones</p>
              <div className="grid sm:grid-cols-2 gap-2">
                {zones.map(z => {
                  const holder = takenBy.get(z._id)
                  return (
                    <label key={z._id} className={`flex items-center gap-2 border rounded px-3 py-2 text-[13px] ${holder ? 'opacity-50' : ''}`}>
                      <input type="checkbox" disabled={!!holder} checked={form.zoneIds.includes(z._id)}
                        onChange={e => setForm({ ...form, zoneIds: e.target.checked ? [...form.zoneIds, z._id] : form.zoneIds.filter(x => x !== z._id) })} />
                      <span className="flex-1">{z.name}</span>
                      {holder && <span className="text-[11px] text-gray-500">{holder}</span>}
                    </label>
                  )
                })}
              </div>
            </div>

            <div className="border-t pt-4">
              <p className="text-[13px] font-semibold text-[#495057] mb-2">Subscription plan</p>
              {plans.length === 0 ? (
                <p className="text-[13px] text-gray-500">No plans yet — add one under <a href="/zone-plans" className="text-primary underline">Subscription Plans</a>.</p>
              ) : (
                <div className="grid sm:grid-cols-2 gap-3">
                  <label className="text-[13px] text-[#495057]">Plan
                    <select className={input} value={form.planId} onChange={e => setForm({ ...form, planId: e.target.value })}>
                      <option value="">No plan yet (cannot sign in)</option>
                      {plans.map(p => <option key={p._id} value={p._id}>{p.name} — {p.months} mo — ₹{p.price.toLocaleString('en-IN')}</option>)}
                    </select>
                  </label>
                  <label className="text-[13px] text-[#495057]">Payment ref (UPI / bank)<input className={input} value={form.paymentRef} onChange={e => setForm({ ...form, paymentRef: e.target.value })} /></label>
                </div>
              )}
            </div>

            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setShowAdd(false)} className="px-4 py-2 rounded border text-[13px]">Cancel</button>
              <button type="submit" disabled={saving} className="px-4 py-2 rounded bg-primary text-white text-[13px] font-medium disabled:opacity-60">
                {saving ? 'Saving…' : 'Create'}
              </button>
            </div>
          </form>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
