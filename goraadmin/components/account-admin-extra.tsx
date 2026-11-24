'use client'
import { useState } from 'react'
import { Modal } from '@/components/ui/modal'

const input = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500'
type ToastFn = (t: { msg: string; type: 'success' | 'error' }) => void

/** Upload one image through /api/upload; returns its URL or throws. */
export async function uploadImage(f: File): Promise<string> {
  const fd = new FormData(); fd.append('file', f)
  const r = await fetch('/api/upload', { method: 'POST', body: fd })
  const d = await r.json().catch(() => ({}))
  if (!r.ok || !d.url) throw new Error(d.error || 'Upload failed')
  return d.url
}

export function PhotoSlot({ label, url, onChange, onError }: { label: string; url: string; onChange: (u: string) => void; onError: (m: string) => void }) {
  const [busy, setBusy] = useState(false)
  return (
    <div>
      <span className="block text-xs font-medium text-gray-500 mb-1">{label}</span>
      <label className="relative flex h-28 cursor-pointer items-center justify-center overflow-hidden rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 text-xs text-gray-500 hover:border-primary">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {url ? <img src={url} alt={label} className="h-full w-full object-cover" /> : <span>{busy ? 'Uploading…' : 'Upload photo'}</span>}
        {url && <span className="absolute bottom-1 right-1 rounded bg-black/60 px-1.5 py-0.5 text-[10px] text-white">{busy ? 'Uploading…' : 'Replace'}</span>}
        <input type="file" accept="image/*" className="hidden" aria-label={`${label} photo`} onChange={async e => {
          const f = e.target.files?.[0]; if (!f) return
          setBusy(true)
          try { onChange(await uploadImage(f)) } catch (err: any) { onError(err.message) }
          setBusy(false)
        }} />
      </label>
    </div>
  )
}

/**
 * Edit one of a driver's documents (number, expiry, photos, status), or add a
 * new one of any admin-defined document type.
 */
export function DriverDocModal({ driverId, doc, docTypes, presetType, onClose, onSaved, onToast }: {
  driverId: string
  doc?: any                 // existing document, or undefined to add
  docTypes: any[]
  presetType?: string       // add: the document type to start with
  onClose: () => void
  onSaved: (driver: any) => void
  onToast: ToastFn
}) {
  const adding = !doc
  const [form, setForm] = useState<any>(() => ({
    type: doc?.type || presetType || docTypes[0]?.key || '',
    number: doc?.number || '', expiryDate: doc?.expiryDate || '',
    frontUrl: doc?.frontUrl || doc?.fileUrl || '', backUrl: doc?.backUrl || '',
    status: doc?.status || 'verified',
  }))
  const [saving, setSaving] = useState(false)
  const spec = docTypes.find(t => t.key === form.type)
    || { needsNumber: true, numberLabel: 'Document number', needsBack: !!doc?.backUrl, needsExpiry: !!doc?.expiryDate, frontLabel: 'Front side', backLabel: 'Back side' }
  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    const body: any = { number: form.number, expiryDate: form.expiryDate, frontUrl: form.frontUrl, backUrl: form.backUrl, status: form.status }
    if (adding) body.type = form.type
    const res = await fetch(adding ? `/api/drivers/${driverId}/documents` : `/api/drivers/${driverId}/documents/${doc._id}`, {
      method: adding ? 'POST' : 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    })
    const d = await res.json().catch(() => ({}))
    setSaving(false)
    if (!res.ok) { onToast({ msg: d.error || 'Could not save', type: 'error' }); return }
    onSaved(d.driver); onToast({ msg: adding ? 'Document added' : 'Document saved', type: 'success' }); onClose()
  }
  return (
    <Modal title={adding ? 'Add document' : `Edit — ${doc.name}`} onClose={onClose}>
      <form onSubmit={save} className="space-y-3 text-sm">
        {adding && (
          <label className="block"><span className="block text-xs font-medium text-gray-500 mb-1">Document</span>
            <select className={`${input} bg-white`} value={form.type} onChange={e => setForm({ ...form, type: e.target.value })}>
              {docTypes.map(t => <option key={t.key} value={t.key}>{t.name}</option>)}
            </select>
          </label>
        )}
        <div className="grid grid-cols-2 gap-3">
          {spec.needsNumber !== false && (
            <label className="block col-span-2"><span className="block text-xs font-medium text-gray-500 mb-1">{spec.numberLabel || 'Document number'}</span>
              <input className={input} value={form.number} onChange={e => setForm({ ...form, number: e.target.value })} /></label>
          )}
          <PhotoSlot label={spec.frontLabel || 'Front side'} url={form.frontUrl} onChange={u => setForm((f: any) => ({ ...f, frontUrl: u }))} onError={m => onToast({ msg: m, type: 'error' })} />
          {(spec.needsBack || form.backUrl) && (
            <PhotoSlot label={spec.backLabel || 'Back side'} url={form.backUrl} onChange={u => setForm((f: any) => ({ ...f, backUrl: u }))} onError={m => onToast({ msg: m, type: 'error' })} />
          )}
          {(spec.needsExpiry || form.expiryDate) && (
            <label className="block"><span className="block text-xs font-medium text-gray-500 mb-1">Expiry date</span>
              <input type="date" className={input} value={form.expiryDate} onChange={e => setForm({ ...form, expiryDate: e.target.value })} /></label>
          )}
          <label className="block"><span className="block text-xs font-medium text-gray-500 mb-1">Status</span>
            <select className={`${input} bg-white`} value={form.status} onChange={e => setForm({ ...form, status: e.target.value })}>
              <option value="pending">Pending</option><option value="verified">Verified</option><option value="rejected">Rejected</option>
            </select>
          </label>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <button type="button" onClick={onClose} className="px-4 py-2 border rounded-lg">Cancel</button>
          <button type="submit" disabled={saving} className="px-4 py-2 bg-primary text-white rounded-lg font-semibold disabled:opacity-60">{saving ? 'Saving…' : 'Save'}</button>
        </div>
      </form>
    </Modal>
  )
}

/** A photo on a rider (profile / ID) the admin can replace. */
export function RiderPhotoCard({ userId, label, field, url, onSaved, onToast }: {
  userId: string; label: string; field: 'profilePicUrl' | 'idPhotoUrl'; url: string
  onSaved: (user: any) => void; onToast: ToastFn
}) {
  const save = async (u: string) => {
    const res = await fetch(`/api/users/${userId}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ [field]: u }) })
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { onToast({ msg: d.error || 'Could not save', type: 'error' }); return }
    onSaved(d); onToast({ msg: `${label} updated`, type: 'success' })
  }
  return <PhotoSlot label={label} url={url || ''} onChange={save} onError={m => onToast({ msg: m, type: 'error' })} />
}
