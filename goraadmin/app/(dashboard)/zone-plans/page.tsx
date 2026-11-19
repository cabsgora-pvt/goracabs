'use client'
import { useCallback, useEffect, useState } from 'react'
import { Plus, Edit2, Trash2 } from 'lucide-react'
import { Header } from '@/components/header'
import { FranchiseOffBanner } from '@/components/franchise-mode'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { ZONE_FEATURES } from '@/lib/zone-features'

type Plan = { _id: string; name: string; months: number; price: number; description?: string; isActive: boolean; features?: string[] }
const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'
const empty = { name: '', months: '12', price: '', description: '', features: ['pricing', 'reports', 'live_map'] as string[] }

// Subscription plans the super admin gives zone admins (franchise).
export default function ZonePlansPage() {
  const [plans, setPlans] = useState<Plan[] | null>(null)
  const [editing, setEditing] = useState<Plan | null>(null)
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState(empty)
  const [saving, setSaving] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => {
    fetch('/api/zone-plans').then(r => r.json()).then(d => setPlans(d.plans || [])).catch(() => setPlans([]))
  }, [])
  useEffect(() => { load() }, [load])

  const startNew = () => { setEditing(null); setForm(empty); setOpen(true) }
  const startEdit = (p: Plan) => { setEditing(p); setForm({ name: p.name, months: String(p.months), price: String(p.price), description: p.description || '', features: p.features || [] }); setOpen(true) }

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      const res = await fetch(editing ? `/api/zone-plans/${editing._id}` : '/api/zone-plans', {
        method: editing ? 'PUT' : 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: form.name, months: Number(form.months), price: Number(form.price), description: form.description, features: form.features }),
      })
      const d = await res.json()
      if (!res.ok) { setToast({ msg: d.error || 'Could not save', type: 'error' }); return }
      setToast({ msg: editing ? 'Plan updated' : 'Plan created', type: 'success' })
      setOpen(false); load()
    } finally { setSaving(false) }
  }

  const toggle = async (p: Plan) => {
    await fetch(`/api/zone-plans/${p._id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ isActive: !p.isActive }) })
    load()
  }
  const remove = async (p: Plan) => {
    if (!confirm(`Delete plan "${p.name}"? Payments already made with it are kept.`)) return
    await fetch(`/api/zone-plans/${p._id}`, { method: 'DELETE' })
    load()
  }

  return (
    <div>
      <Header title="Subscription Plans" />
      <div className="p-6 space-y-5">
        <FranchiseOffBanner />
        <PageHeader
          title="Zone Admin Subscription Plans"
          subtitle="Plans you give zone admins. Choose one when adding or renewing a zone admin."
          action={<button type="button" onClick={startNew} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px] font-medium"><Plus className="w-4 h-4" /> Add Plan</button>}
        />
        {!plans ? <p className="text-gray-400">Loading…</p> : plans.length === 0 ? (
          <div className="bg-white rounded shadow-sm p-10 text-center text-gray-500">No plans yet. Add one, e.g. “Yearly — 12 months — ₹50,000”.</div>
        ) : (
          <div className="grid sm:grid-cols-2 xl:grid-cols-3 gap-4">
            {plans.map(p => (
              <div key={p._id} className={`bg-white rounded shadow-sm p-5 ${p.isActive ? '' : 'opacity-60'}`}>
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <h5 className="text-[16px] font-semibold text-[#495057]">{p.name}</h5>
                    <p className="text-[13px] text-[#878a99]">{p.months} month{p.months > 1 ? 's' : ''}</p>
                  </div>
                  <span className={`px-2 py-[3px] rounded text-[10.5px] font-semibold uppercase ${p.isActive ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-600'}`}>
                    {p.isActive ? 'Active' : 'Off'}
                  </span>
                </div>
                <p className="text-[26px] font-semibold text-primary mt-3">₹{Math.round(p.price).toLocaleString('en-IN')}</p>
                {p.description && <p className="text-[13px] text-gray-500 mt-2">{p.description}</p>}
                <div className="flex flex-wrap gap-1.5 mt-3">
                  {ZONE_FEATURES.filter(f => (p.features || []).includes(f.key)).map(f => (
                    <span key={f.key} className="px-2 py-0.5 rounded bg-blue-50 text-blue-700 text-[11px] font-medium">{f.label}</span>
                  ))}
                </div>
                <div className="flex items-center gap-2 mt-4 pt-3 border-t border-[#e9ebec]">
                  <button type="button" onClick={() => startEdit(p)} className="inline-flex items-center gap-1 text-[13px] text-primary"><Edit2 className="w-4 h-4" /> Edit</button>
                  <button type="button" onClick={() => toggle(p)} className="text-[13px] text-[#495057] ml-2">{p.isActive ? 'Turn off' : 'Turn on'}</button>
                  <button type="button" onClick={() => remove(p)} className="inline-flex items-center gap-1 text-[13px] text-red-600 ml-auto"><Trash2 className="w-4 h-4" /> Delete</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {open && (
        <Modal title={editing ? 'Edit Plan' : 'Add Plan'} onClose={() => setOpen(false)}>
          <form onSubmit={save} className="space-y-3">
            <label className="block text-[13px] text-[#495057]">Plan name *<input className={input} required placeholder="e.g. Yearly" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
            <div className="grid grid-cols-2 gap-3">
              <label className="text-[13px] text-[#495057]">Duration (months) *<input type="number" min={1} max={60} required className={input} value={form.months} onChange={e => setForm({ ...form, months: e.target.value })} /></label>
              <label className="text-[13px] text-[#495057]">Price ₹ *<input type="number" min={0} required className={input} value={form.price} onChange={e => setForm({ ...form, price: e.target.value })} /></label>
            </div>
            <label className="block text-[13px] text-[#495057]">Description<textarea rows={3} className={input} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label>
            <div>
              <p className="text-[13px] font-semibold text-[#495057] mb-2">What a zone admin on this plan can do</p>
              <div className="grid grid-cols-2 gap-2">
                {ZONE_FEATURES.map(f => (
                  <label key={f.key} className="flex items-center gap-2 text-[13px] border rounded px-3 py-2">
                    <input type="checkbox" checked={form.features.includes(f.key)}
                      onChange={e => setForm({ ...form, features: e.target.checked ? [...form.features, f.key] : form.features.filter(x => x !== f.key) })} />
                    {f.label}
                  </label>
                ))}
              </div>
              <p className="text-xs text-gray-500 mt-1">Dashboard, drivers list, rides and profile are always included.</p>
            </div>
            {editing && <p className="text-xs text-gray-500">Changes apply to new assignments and renewals; past payments keep their amount.</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setOpen(false)} className="px-4 py-2 rounded border text-[13px]">Cancel</button>
              <button type="submit" disabled={saving} className="px-4 py-2 rounded bg-primary text-white text-[13px] font-medium disabled:opacity-60">{saving ? 'Saving…' : 'Save'}</button>
            </div>
          </form>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
