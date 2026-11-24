'use client'
import { useCallback, useEffect, useState } from 'react'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Pencil, Trash2, PawPrint, Luggage, Accessibility, Snowflake, CigaretteOff, Baby, Music, Star } from 'lucide-react'

const input = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500'
const ICONS: Record<string, any> = { pets: PawPrint, luggage: Luggage, accessible: Accessibility, ac_unit: Snowflake, smoke_free: CigaretteOff, child_care: Baby, music_note: Music, star: Star }
const ICON_LABEL: Record<string, string> = { pets: 'Pets', luggage: 'Luggage', accessible: 'Wheelchair', ac_unit: 'AC', smoke_free: 'No smoking', child_care: 'Child seat', music_note: 'Music', star: 'Star' }
const SERVICES = [['taxi', 'Taxi'], ['rental', 'Rental'], ['outstation', 'Outstation'], ['delivery', 'Parcel'], ['hire_driver', 'Hire driver']] as const
const empty = { name: '', description: '', icon: 'star', services: ['taxi', 'rental', 'outstation'], isActive: true }

// Ride preference types (new types are added here). Riders pick them when
// booking; drivers turn on the ones they offer in Trip preferences; dispatch
// tries drivers who offer all of a ride's preferences first.
export default function RidePreferencesPage() {
  const [rows, setRows] = useState<any[]>([])
  const [edit, setEdit] = useState<any | null>(null)
  const [form, setForm] = useState<any>(empty)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => {
    fetch('/api/ride-preferences?all=1').then(r => r.json()).then(d => setRows(d.preferences || [])).catch(() => {})
  }, [])
  useEffect(() => { load() }, [load])

  const open = (row?: any) => { setEdit(row || {}); setForm(row ? { ...row } : empty) }
  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.services?.length) { setToast({ msg: 'Pick at least one service', type: 'error' }); return }
    const isNew = !edit?.id
    const res = await fetch(isNew ? '/api/ride-preferences' : `/api/ride-preferences/${edit.id}`, {
      method: isNew ? 'POST' : 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
    })
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { setToast({ msg: d.error || 'Could not save', type: 'error' }); return }
    setToast({ msg: isNew ? 'Preference added' : 'Saved', type: 'success' }); setEdit(null); load()
  }
  const toggle = async (row: any) => {
    await fetch(`/api/ride-preferences/${row.id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ isActive: !row.isActive }) })
    load()
  }
  const remove = async (row: any) => {
    if (!confirm(`Delete "${row.name}"? It is also removed from every driver who offered it.`)) return
    await fetch(`/api/ride-preferences/${row.id}`, { method: 'DELETE' }); load()
  }
  const svc = (s: string) => form.services?.includes(s)

  return (
    <div>
      <Header title="Ride Preferences" />
      <div className="p-6 space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <p className="text-sm text-gray-600 max-w-2xl">Riders can ask for these when booking (for example <b>Pet friendly</b> or <b>Extra luggage</b>). Drivers switch on the ones they offer in <b>Trip preferences</b>. A ride goes first to drivers who offer everything asked for, then to everyone if none is free.</p>
          <button type="button" onClick={() => open()} className="inline-flex items-center gap-2 bg-primary text-white px-4 py-2 rounded text-sm"><Plus className="w-4 h-4" />New preference</button>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {rows.length === 0 && <p className="text-sm text-gray-400">No preferences yet — add the first one.</p>}
          {rows.map(r => {
            const Icon = ICONS[r.icon] || Star
            return (
              <div key={r.id} className={`bg-white rounded-lg shadow-sm p-4 flex gap-3 ${r.isActive ? '' : 'opacity-60'}`}>
                <div className="w-11 h-11 rounded-full bg-primary/10 text-primary flex items-center justify-center flex-shrink-0"><Icon className="w-5 h-5" /></div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <p className="font-semibold text-gray-800 truncate">{r.name}</p>
                    <button type="button" onClick={() => toggle(r)} className={`px-2 py-0.5 rounded text-[11px] font-semibold ${r.isActive ? 'bg-green-100 text-green-700' : 'bg-gray-200 text-gray-600'}`}>{r.isActive ? 'On' : 'Off'}</button>
                  </div>
                  {r.description && <p className="text-xs text-gray-500 mt-0.5">{r.description}</p>}
                  <div className="flex flex-wrap gap-1 mt-2">
                    {r.services.map((s: string) => <span key={s} className="text-[10.5px] bg-gray-100 text-gray-600 px-1.5 py-0.5 rounded">{SERVICES.find(x => x[0] === s)?.[1] || s}</span>)}
                  </div>
                </div>
                <div className="flex flex-col gap-1">
                  <button type="button" title="Edit" onClick={() => open(r)} className="p-1 text-gray-500 hover:text-primary"><Pencil className="w-4 h-4" /></button>
                  <button type="button" title="Delete" onClick={() => remove(r)} className="p-1 text-gray-500 hover:text-red-600"><Trash2 className="w-4 h-4" /></button>
                </div>
              </div>
            )
          })}
        </div>
      </div>
      {edit && (
        <Modal title={edit.id ? 'Edit preference' : 'New preference'} onClose={() => setEdit(null)}>
          <form onSubmit={save} className="space-y-3 text-sm">
            <label className="block">Name<input required className={input} value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Pet friendly" /></label>
            <label className="block">Short description<input className={input} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Small pets allowed in the car" /></label>
            <div>
              <p className="mb-1">Icon</p>
              <div className="flex flex-wrap gap-2">
                {Object.keys(ICONS).map(k => {
                  const I = ICONS[k]
                  return <button type="button" key={k} title={ICON_LABEL[k]} onClick={() => setForm({ ...form, icon: k })}
                    className={`w-10 h-10 rounded-lg border flex items-center justify-center ${form.icon === k ? 'border-primary bg-primary/10 text-primary' : 'text-gray-500'}`}><I className="w-5 h-5" /></button>
                })}
              </div>
            </div>
            <div>
              <p className="mb-1">Services</p>
              <div className="flex flex-wrap gap-3">
                {SERVICES.map(([k, l]) => (
                  <label key={k} className="flex items-center gap-1.5"><input type="checkbox" checked={svc(k)}
                    onChange={e => setForm({ ...form, services: e.target.checked ? [...form.services, k] : form.services.filter((x: string) => x !== k) })} />{l}</label>
                ))}
              </div>
            </div>
            <label className="flex items-center gap-2"><input type="checkbox" checked={!!form.isActive} onChange={e => setForm({ ...form, isActive: e.target.checked })} />Shown in the apps</label>
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
