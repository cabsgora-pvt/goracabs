'use client'
import { useCallback, useEffect, useState } from 'react'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Pencil, Trash2, FileText, ArrowUp, ArrowDown } from 'lucide-react'

const input = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500'
const CATEGORIES = [
  { value: 'identity', label: 'Identity' },
  { value: 'vehicle', label: 'Vehicle' },
  { value: 'driving', label: 'Driving licence' },
  { value: 'other', label: 'Other' },
]
const CAT_LABEL: Record<string, string> = Object.fromEntries(CATEGORIES.map(c => [c.value, c.label]))
const empty = {
  name: '', category: 'other', description: '', needsNumber: true, numberLabel: '',
  frontLabel: 'Front side', backLabel: 'Back side', needsBack: false, needsExpiry: false,
  required: true, isActive: true, vehicleTypes: [] as string[], order: '' as any,
}

/**
 * The documents a driver uploads at registration, fully editable by the admin:
 * name, document type, instructions, which fields and photos it needs, which
 * vehicle types it is asked of, required or optional, on/off and order. The
 * driver app reads this list, and the server checks submissions against it.
 */
export function DocumentTypesManager({ compact = false }: { compact?: boolean }) {
  const [rows, setRows] = useState<any[]>([])
  const [vehicleTypes, setVehicleTypes] = useState<string[]>([])
  const [edit, setEdit] = useState<any | null>(null)
  const [form, setForm] = useState<any>(empty)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => {
    fetch('/api/document-types?all=1').then(r => r.json()).then(d => setRows(d.documents || [])).catch(() => {})
  }, [])
  useEffect(() => {
    load()
    fetch('/api/vehicles/types').then(r => r.json()).then(d => setVehicleTypes((d.types || []).map((v: any) => v.name).filter(Boolean))).catch(() => {})
  }, [load])

  const put = async (id: string, body: any) => {
    const res = await fetch(`/api/document-types/${id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    if (!res.ok) { const d = await res.json().catch(() => ({})); setToast({ msg: d.error || 'Could not save', type: 'error' }) }
    return res.ok
  }
  const open = (row?: any) => { setEdit(row || {}); setForm(row ? { ...empty, ...row } : empty) }
  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    const isNew = !edit?.id
    const body = { ...form, order: form.order === '' ? undefined : Number(form.order) }
    const res = await fetch(isNew ? '/api/document-types' : `/api/document-types/${edit.id}`, {
      method: isNew ? 'POST' : 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    })
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { setToast({ msg: d.error || 'Could not save', type: 'error' }); return }
    setToast({ msg: isNew ? 'Document added' : 'Document saved', type: 'success' }); setEdit(null); load()
  }
  const toggle = async (row: any, key: 'required' | 'isActive') => { if (await put(row.id, { [key]: !row[key] })) load() }
  const move = async (i: number, dir: -1 | 1) => {
    const j = i + dir
    if (j < 0 || j >= rows.length) return
    const a = rows[i], b = rows[j]
    // Swap positions; give distinct numbers when two rows share one.
    const ao = a.order === b.order ? j + 1 : b.order, bo = a.order === b.order ? i + 1 : a.order
    await Promise.all([put(a.id, { order: ao }), put(b.id, { order: bo })]); load()
  }
  const remove = async (row: any) => {
    if (!confirm(`Remove "${row.name}"? Drivers will no longer be asked for it. Files already uploaded stay.`)) return
    await fetch(`/api/document-types/${row.id}`, { method: 'DELETE' }); load()
  }
  const toggleVt = (v: string) => {
    const cur: string[] = form.vehicleTypes || []
    setForm({ ...form, vehicleTypes: cur.includes(v) ? cur.filter(x => x !== v) : [...cur, v] })
  }
  const needs = (r: any) => [r.needsNumber ? (r.numberLabel || 'Number') : null, r.frontLabel || 'Front side', r.needsBack ? (r.backLabel || 'Back side') : null, r.needsExpiry ? 'Expiry date' : null].filter(Boolean).join(' · ')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <p className={`text-sm text-gray-600 ${compact ? 'max-w-xl' : 'max-w-2xl'}`}>
          These documents are asked for in the driver app during registration, in this order. <b>Required</b> ones must be uploaded to finish
          (the server checks it too); turn a document <b>off</b> to stop asking for it. Limit one to some vehicle types if only they need it.
        </p>
        <button type="button" onClick={() => open()} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-sm"><Plus className="w-4 h-4" />Add document</button>
      </div>
      <div className="bg-white rounded shadow-sm overflow-x-auto border border-gray-100">
        <table className="w-full text-[13px]">
          <thead><tr>{['', 'Document', 'Type', 'Driver fills in', 'Vehicle types', 'Required', 'Shown in app', ''].map((h, i) => <th key={i} className="text-left px-3 py-3">{h}</th>)}</tr></thead>
          <tbody className="divide-y">
            {rows.map((r, i) => (
              <tr key={r.id} className={r.isActive ? '' : 'opacity-50'}>
                <td className="px-2 py-3 whitespace-nowrap">
                  <button type="button" title="Move up" aria-label={`Move ${r.name} up`} disabled={i === 0} onClick={() => move(i, -1)} className="p-1 text-gray-400 hover:text-primary disabled:opacity-30"><ArrowUp className="w-3.5 h-3.5" /></button>
                  <button type="button" title="Move down" aria-label={`Move ${r.name} down`} disabled={i === rows.length - 1} onClick={() => move(i, 1)} className="p-1 text-gray-400 hover:text-primary disabled:opacity-30"><ArrowDown className="w-3.5 h-3.5" /></button>
                </td>
                <td className="px-3 py-3 font-medium">
                  <span className="inline-flex items-center gap-2"><FileText className="w-4 h-4 text-gray-400" />{r.name}</span>
                  {r.description && <span className="block text-[11.5px] font-normal text-gray-500 max-w-xs truncate">{r.description}</span>}
                </td>
                <td className="px-3 py-3">{CAT_LABEL[r.category] || 'Other'}</td>
                <td className="px-3 py-3 text-gray-600">{needs(r)}</td>
                <td className="px-3 py-3 text-gray-600">{r.vehicleTypes?.length ? r.vehicleTypes.join(', ') : 'All'}</td>
                <td className="px-3 py-3"><button type="button" onClick={() => toggle(r, 'required')} className={`px-2 py-0.5 rounded text-[11px] font-semibold ${r.required ? 'bg-red-100 text-red-700' : 'bg-gray-100 text-gray-600'}`}>{r.required ? 'Required' : 'Optional'}</button></td>
                <td className="px-3 py-3"><button type="button" onClick={() => toggle(r, 'isActive')} className={`px-2 py-0.5 rounded text-[11px] font-semibold ${r.isActive ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-600'}`}>{r.isActive ? 'On' : 'Off'}</button></td>
                <td className="px-3 py-3 text-right whitespace-nowrap">
                  <button type="button" title="Edit" aria-label={`Edit ${r.name}`} onClick={() => open(r)} className="p-1.5 text-gray-500 hover:text-primary"><Pencil className="w-4 h-4" /></button>
                  <button type="button" title="Remove" aria-label={`Remove ${r.name}`} onClick={() => remove(r)} className="p-1.5 text-gray-500 hover:text-red-600"><Trash2 className="w-4 h-4" /></button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {edit && (
        <Modal title={edit.id ? `Edit document — ${edit.name}` : 'Add document'} onClose={() => setEdit(null)}>
          <form onSubmit={save} className="space-y-3 text-sm">
            <div className="grid grid-cols-2 gap-3">
              <label className="block col-span-2">Document name<input required className={input} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Police Verification" /></label>
              <label className="block">Document type
                <select className={`${input} bg-white`} value={form.category} onChange={e => setForm({ ...form, category: e.target.value })}>
                  {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
                </select>
              </label>
              <label className="block">Order<input type="number" className={input} value={form.order} onChange={e => setForm({ ...form, order: e.target.value })} placeholder="auto" /></label>
              <label className="block col-span-2">Instructions for the driver<textarea rows={2} className={input} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Upload a clear photo of the certificate from your police station" /></label>
            </div>
            <fieldset className="border rounded-lg p-3 space-y-2">
              <legend className="px-1 text-xs font-semibold text-gray-500">What the driver fills in</legend>
              <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.needsNumber} onChange={e => setForm({ ...form, needsNumber: e.target.checked })} />Document number</label>
              {form.needsNumber && <label className="block">Number field label<input className={input} value={form.numberLabel} onChange={e => setForm({ ...form, numberLabel: e.target.value })} placeholder="Certificate Number" /></label>}
              <label className="block">First photo label<input className={input} value={form.frontLabel} onChange={e => setForm({ ...form, frontLabel: e.target.value })} placeholder="Front side" /></label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.needsBack} onChange={e => setForm({ ...form, needsBack: e.target.checked })} />Second photo (back side)</label>
              {form.needsBack && <label className="block">Second photo label<input className={input} value={form.backLabel} onChange={e => setForm({ ...form, backLabel: e.target.value })} placeholder="Back side" /></label>}
              <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.needsExpiry} onChange={e => setForm({ ...form, needsExpiry: e.target.checked })} />Expiry date</label>
            </fieldset>
            <fieldset className="border rounded-lg p-3">
              <legend className="px-1 text-xs font-semibold text-gray-500">Ask drivers of these vehicle types (none ticked = all)</legend>
              <div className="flex flex-wrap gap-3">
                {vehicleTypes.length === 0 && <span className="text-xs text-gray-400">No vehicle types yet</span>}
                {vehicleTypes.map(v => (
                  <label key={v} className="flex items-center gap-1.5"><input type="checkbox" checked={(form.vehicleTypes || []).includes(v)} onChange={() => toggleVt(v)} />{v}</label>
                ))}
              </div>
            </fieldset>
            <div className="flex gap-5">
              <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.required} onChange={e => setForm({ ...form, required: e.target.checked })} />Required</label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.isActive} onChange={e => setForm({ ...form, isActive: e.target.checked })} />Shown in app</label>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button type="button" onClick={() => setEdit(null)} className="px-4 py-2 border rounded-lg">Cancel</button>
              <button type="submit" className="px-4 py-2 bg-primary text-white rounded-lg font-semibold">Save</button>
            </div>
          </form>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
