'use client'
import { useCallback, useEffect, useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { zoneFetch, useZoneSession } from '@/components/zone-shell'
import { fmtDate } from '@/lib/zone-admin-ui'

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'
const empty = { code: '', type: 'percent', value: '', maxDiscount: '', minOrderAmount: '', maxUses: '', expiryDate: '' }

// The zone admin's own promo codes — valid only in their zones.
export default function ZonePromos() {
  const session = useZoneSession()
  const canEdit = !session?.readOnly
  const [d, setD] = useState<any>(null)
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState(empty)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => { zoneFetch('/api/zone-admin/promos').then(r => r.json()).then(setD).catch(() => {}) }, [])
  useEffect(() => { load() }, [load])

  const create = async (e: React.FormEvent) => {
    e.preventDefault()
    const r = await zoneFetch('/api/zone-admin/promos', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, value: Number(form.value), maxDiscount: Number(form.maxDiscount) || 0, minOrderAmount: Number(form.minOrderAmount) || 0, maxUses: Number(form.maxUses) || 0 }),
    })
    const x = await r.json()
    if (!r.ok) { setToast({ msg: x.error || 'Could not create', type: 'error' }); return }
    setToast({ msg: 'Promo code created', type: 'success' }); setOpen(false); setForm(empty); load()
  }
  const toggle = async (p: any) => {
    await zoneFetch(`/api/zone-admin/promos/${p._id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ isActive: !p.isActive }) })
    load()
  }
  const remove = async (p: any) => {
    if (!confirm(`Delete ${p.code}?`)) return
    await zoneFetch(`/api/zone-admin/promos/${p._id}`, { method: 'DELETE' }); load()
  }

  return (
    <div>
      <Header title="Promo Codes" />
      <div className="p-6 space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="text-[13px] text-gray-600 max-w-2xl">
            <p>Codes you create will work only for rides booked in your zones.</p>
            {d && !d.live && <p className="text-yellow-700 mt-1"><b>Coming soon.</b> Zone promo codes switch on with Gora&apos;s next rider app update; until then new codes cannot be created.</p>}
            {d?.caps && <p className="text-gray-500 mt-1">Limits: up to {d.caps.maxPercent}% (max ₹{d.caps.maxDiscount} off) or ₹{d.caps.maxFlat} flat.</p>}
          </div>
          {canEdit && d?.live && <button type="button" onClick={() => setOpen(true)} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px]"><Plus className="w-4 h-4" /> New code</button>}
        </div>
        <div className="bg-white rounded shadow-sm overflow-x-auto">
          <table className="w-full text-[13px]">
            <thead><tr>{['Code', 'Discount', 'Min fare', 'Used', 'Expires', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
            <tbody className="divide-y">
              {!d ? <tr><td colSpan={7} className="text-center py-8 text-gray-400">Loading…</td></tr> : d.promos.length === 0 ? <tr><td colSpan={7} className="text-center py-8 text-gray-400">No codes yet</td></tr> :
                d.promos.map((p: any) => (
                  <tr key={p._id}>
                    <td className="px-4 py-3 font-semibold tracking-wide">{p.code}</td>
                    <td className="px-4 py-3">{p.type === 'flat' ? `₹${p.value}` : `${p.value}%${p.maxDiscount ? ` (max ₹${p.maxDiscount})` : ''}`}</td>
                    <td className="px-4 py-3">{p.minOrderAmount ? `₹${p.minOrderAmount}` : '—'}</td>
                    <td className="px-4 py-3">{p.usedCount || 0}{p.maxUses ? ` / ${p.maxUses}` : ''}</td>
                    <td className="px-4 py-3">{p.expiryDate ? fmtDate(p.expiryDate) : '—'}</td>
                    <td className="px-4 py-3">
                      <button type="button" disabled={!canEdit} onClick={() => toggle(p)}
                        className={`px-2 py-[3px] rounded text-[10.5px] font-semibold uppercase ${p.isActive ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-600'}`}>{p.isActive ? 'On' : 'Off'}</button>
                    </td>
                    <td className="px-4 py-3 text-right">{canEdit && <button type="button" onClick={() => remove(p)} className="text-red-600"><Trash2 className="w-4 h-4" /></button>}</td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>
      {open && (
        <Modal title="New promo code" onClose={() => setOpen(false)}>
          <form onSubmit={create} className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <label className="text-[13px]">Code<input className={`${input} uppercase`} required value={form.code} onChange={e => setForm({ ...form, code: e.target.value.toUpperCase() })} placeholder="RAJKOT50" /></label>
              <label className="text-[13px]">Type
                <select className={input} value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}>
                  <option value="percent">Percent off</option><option value="flat">Flat ₹ off</option>
                </select>
              </label>
              <label className="text-[13px]">{form.type === 'flat' ? 'Amount ₹' : 'Percent %'}<input type="number" min={1} required className={input} value={form.value} onChange={e => setForm({ ...form, value: e.target.value })} /></label>
              {form.type === 'percent' && <label className="text-[13px]">Max discount ₹<input type="number" min={1} required className={input} value={form.maxDiscount} onChange={e => setForm({ ...form, maxDiscount: e.target.value })} /></label>}
              <label className="text-[13px]">Min fare ₹<input type="number" min={0} className={input} value={form.minOrderAmount} onChange={e => setForm({ ...form, minOrderAmount: e.target.value })} /></label>
              <label className="text-[13px]">Max uses (0 = no limit)<input type="number" min={0} className={input} value={form.maxUses} onChange={e => setForm({ ...form, maxUses: e.target.value })} /></label>
              <label className="text-[13px]">Expires on<input type="date" className={input} value={form.expiryDate} onChange={e => setForm({ ...form, expiryDate: e.target.value })} /></label>
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setOpen(false)} className="px-4 py-2 rounded border text-[13px]">Cancel</button>
              <button type="submit" className="px-4 py-2 rounded bg-primary text-white text-[13px]">Create</button>
            </div>
          </form>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
