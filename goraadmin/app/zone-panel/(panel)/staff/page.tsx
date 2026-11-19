'use client'
import { useCallback, useEffect, useState } from 'react'
import { Plus } from 'lucide-react'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { zoneFetch, useZoneSession } from '@/components/zone-shell'
import { ZONE_FEATURES } from '@/lib/zone-features'
import { fmtDate } from '@/lib/zone-admin-ui'

const input = 'w-full border border-[#ced4da] rounded px-3 py-2 text-[13px] focus:outline-none focus:border-[#a0a8c4]'

// Operators the zone admin adds, each with some of the zone admin's own features.
export default function ZoneStaffPage() {
  const session = useZoneSession()
  const canEdit = !session?.readOnly
  const grantable = ZONE_FEATURES.filter(f => f.key !== 'staff' && session?.features.includes(f.key))
  const [d, setD] = useState<any>(null)
  const [edit, setEdit] = useState<any>(null)   // null | 'new' | staff
  const [form, setForm] = useState({ name: '', email: '', phone: '', password: '', permissions: [] as string[] })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => { zoneFetch('/api/zone-admin/staff').then(r => r.json()).then(setD).catch(() => {}) }, [])
  useEffect(() => { load() }, [load])

  const openNew = () => { setForm({ name: '', email: '', phone: '', password: '', permissions: [] }); setEdit('new') }
  const openEdit = (s: any) => { setForm({ name: s.name, email: s.email, phone: s.phone || '', password: '', permissions: s.permissions || [] }); setEdit(s) }

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    const isNew = edit === 'new'
    const r = await zoneFetch(isNew ? '/api/zone-admin/staff' : `/api/zone-admin/staff/${edit._id}`, {
      method: isNew ? 'POST' : 'PUT', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(isNew ? form : { name: form.name, phone: form.phone, permissions: form.permissions, ...(form.password ? { password: form.password } : {}) }),
    })
    const x = await r.json()
    if (!r.ok) { setToast({ msg: x.error || 'Could not save', type: 'error' }); return }
    setToast({ msg: isNew ? 'Staff login created' : 'Saved', type: 'success' }); setEdit(null); load()
  }
  const setStatus = async (s: any, status: string) => {
    await zoneFetch(`/api/zone-admin/staff/${s._id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status }) }); load()
  }
  const remove = async (s: any) => {
    if (!confirm(`Remove ${s.name}'s login?`)) return
    await zoneFetch(`/api/zone-admin/staff/${s._id}`, { method: 'DELETE' }); load()
  }

  return (
    <div>
      <Header title="Staff" />
      <div className="p-6 space-y-4">
        <div className="flex justify-between items-center">
          <p className="text-[13px] text-gray-600">Staff sign in at the same zone panel login and see only what you allow.</p>
          {canEdit && <button type="button" onClick={openNew} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-[13px]"><Plus className="w-4 h-4" /> Add staff</button>}
        </div>
        <div className="bg-white rounded shadow-sm overflow-x-auto">
          <table className="w-full text-[13px]">
            <thead><tr>{['Name', 'Email (login)', 'Can do', 'Last login', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
            <tbody className="divide-y">
              {!d ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">Loading…</td></tr> : d.staff.length === 0 ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">No staff yet</td></tr> :
                d.staff.map((s: any) => (
                  <tr key={s._id}>
                    <td className="px-4 py-3 font-medium">{s.name}{s.passwordResetRequestedAt && <span className="ml-2 text-[10.5px] text-sky-700 bg-sky-50 px-1.5 py-0.5 rounded">Reset requested</span>}</td>
                    <td className="px-4 py-3">{s.email}</td>
                    <td className="px-4 py-3 text-gray-600">{ZONE_FEATURES.filter(f => (s.permissions || []).includes(f.key)).map(f => f.label).join(', ') || 'View only'}</td>
                    <td className="px-4 py-3">{s.lastLoginAt ? fmtDate(s.lastLoginAt) : 'Never'}</td>
                    <td className="px-4 py-3"><span className={`px-2 py-[3px] rounded text-[10.5px] font-semibold uppercase ${s.status === 'active' ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-600'}`}>{s.status}</span></td>
                    <td className="px-4 py-3 text-right whitespace-nowrap space-x-3">
                      {canEdit && <>
                        <button type="button" onClick={() => openEdit(s)} className="text-primary">Edit</button>
                        <button type="button" onClick={() => setStatus(s, s.status === 'active' ? 'blocked' : 'active')} className="text-[#495057]">{s.status === 'active' ? 'Block' : 'Unblock'}</button>
                        <button type="button" onClick={() => remove(s)} className="text-red-600">Remove</button>
                      </>}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>
      {edit && (
        <Modal title={edit === 'new' ? 'Add staff' : `Edit ${edit.name}`} onClose={() => setEdit(null)}>
          <form onSubmit={save} className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <label className="text-[13px]">Name<input className={input} required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
              <label className="text-[13px]">Phone<input className={input} value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} /></label>
              <label className="text-[13px]">Email (login)<input type="email" className={input} required disabled={edit !== 'new'} value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} /></label>
              <label className="text-[13px]">{edit === 'new' ? 'Password (min 8)' : 'New password (optional)'}<input type="text" minLength={8} required={edit === 'new'} className={input} value={form.password} onChange={e => setForm({ ...form, password: e.target.value })} /></label>
            </div>
            <div>
              <p className="text-[13px] font-semibold mb-2">Can do (always: dashboard, drivers list, rides)</p>
              <div className="grid grid-cols-2 gap-2">
                {grantable.map(f => (
                  <label key={f.key} className="flex items-center gap-2 text-[13px] border rounded px-3 py-2">
                    <input type="checkbox" checked={form.permissions.includes(f.key)}
                      onChange={e => setForm({ ...form, permissions: e.target.checked ? [...form.permissions, f.key] : form.permissions.filter(x => x !== f.key) })} />
                    {f.label}
                  </label>
                ))}
              </div>
            </div>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setEdit(null)} className="px-4 py-2 rounded border text-[13px]">Cancel</button>
              <button type="submit" className="px-4 py-2 rounded bg-primary text-white text-[13px]">Save</button>
            </div>
          </form>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
