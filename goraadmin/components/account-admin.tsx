'use client'
import { useEffect, useState } from 'react'
import { Pencil, PauseCircle, PlayCircle, MapPin, History } from 'lucide-react'
import { Modal } from '@/components/ui/modal'

const input = 'w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500'

export type EditField = {
  key: string            // may be nested: 'bankDetails.ifscCode'
  label: string
  type?: 'text' | 'email' | 'tel' | 'select' | 'checkbox' | 'textarea' | 'section'
  options?: { value: string; label: string }[]
  half?: boolean
}

// Reads 'a.b' from an object.
const getPath = (o: any, k: string) => k.split('.').reduce((v, p) => (v == null ? undefined : v[p]), o)

/** "Edit" button + modal for a rider or driver (admin edit mode). Sends only
 *  the changed fields; the API keeps a whitelist of what may change. */
export function EditAccountButton({ title, fields, value, url, onSaved, onToast }: {
  title: string
  fields: EditField[]
  value: any
  url: string
  onSaved: (doc: any) => void
  onToast: (t: { msg: string; type: 'success' | 'error' }) => void
}) {
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const [saving, setSaving] = useState(false)
  const start = () => {
    const f: any = {}
    for (const x of fields) if (x.type !== 'section') f[x.key] = getPath(value, x.key) ?? (x.type === 'checkbox' ? false : '')
    setForm(f); setOpen(true)
  }
  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    const changed: any = {}
    for (const x of fields) {
      if (x.type === 'section') continue
      if ((form[x.key] ?? '') !== (getPath(value, x.key) ?? (x.type === 'checkbox' ? false : ''))) changed[x.key] = form[x.key]
    }
    if (Object.keys(changed).length === 0) { setOpen(false); return }
    setSaving(true)
    const res = await fetch(url, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(changed) })
    const d = await res.json().catch(() => ({}))
    setSaving(false)
    if (!res.ok) { onToast({ msg: d.error || 'Could not save', type: 'error' }); return }
    onSaved(d); setOpen(false); onToast({ msg: 'Changes saved', type: 'success' })
  }
  return (
    <>
      <button type="button" onClick={start}
        className="w-full flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-medium bg-primary text-white hover:bg-primary-dark">
        <Pencil className="w-4 h-4" /> Edit details
      </button>
      {open && (
        <Modal title={title} onClose={() => setOpen(false)}>
          <form onSubmit={save} className="space-y-3">
            <div className="grid grid-cols-2 gap-3 max-h-[65vh] overflow-y-auto pr-1">
              {fields.map(x => x.type === 'section' ? (
                <p key={x.key} className="col-span-2 pt-2 mt-1 border-t text-xs font-semibold uppercase tracking-wide text-gray-500">{x.label}</p>
              ) : (
                <label key={x.key} className={`text-sm text-gray-700 ${x.half ? '' : 'col-span-2'} ${x.type === 'checkbox' ? 'flex items-center gap-2 col-span-1' : ''}`}>
                  {x.type === 'checkbox' ? (
                    <><input type="checkbox" checked={!!form[x.key]} onChange={e => setForm({ ...form, [x.key]: e.target.checked })} /> {x.label}</>
                  ) : (
                    <>
                      <span className="block text-xs font-medium text-gray-500 mb-1">{x.label}</span>
                      {x.type === 'select' ? (
                        <select className={`${input} bg-white`} value={form[x.key] ?? ''} onChange={e => setForm({ ...form, [x.key]: e.target.value })}>
                          <option value="">—</option>
                          {x.options?.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
                        </select>
                      ) : x.type === 'textarea' ? (
                        <textarea className={input} rows={2} value={form[x.key] ?? ''} onChange={e => setForm({ ...form, [x.key]: e.target.value })} />
                      ) : (
                        <input className={input} type={x.type || 'text'} value={form[x.key] ?? ''} onChange={e => setForm({ ...form, [x.key]: e.target.value })} />
                      )}
                    </>
                  )}
                </label>
              ))}
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <button type="button" onClick={() => setOpen(false)} className="px-4 py-2 border rounded-lg text-sm">Cancel</button>
              <button type="submit" disabled={saving} className="px-4 py-2 bg-primary text-white rounded-lg text-sm font-semibold disabled:opacity-60">{saving ? 'Saving…' : 'Save changes'}</button>
            </div>
          </form>
        </Modal>
      )}
    </>
  )
}

const KIND_LABEL: Record<string, string> = { face: 'Wrong face scan', wallet: 'Wallet mis-transaction', manual: 'Held by admin', other: 'Other' }

/** Account hold: shows the current hold (incl. a failed face check) and lets
 *  the admin put the account on hold with a reason, or release it. */
export function HoldCard({ doc, url, isDriver, onChanged, onToast, walletNote }: {
  doc: any
  url: string
  isDriver: boolean
  onChanged: (hold: any) => void
  onToast: (t: { msg: string; type: 'success' | 'error' }) => void
  walletNote?: string
}) {
  const [open, setOpen] = useState(false)
  const [kind, setKind] = useState('manual')
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const hold = doc?.accountHold?.active ? doc.accountHold
    : (isDriver && doc?.faceVerificationRequired ? { active: true, kind: 'face', reason: 'Mid-ride face check did not match (automatic)' } : null)

  const send = async (body: any) => {
    setBusy(true)
    const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    const d = await res.json().catch(() => ({}))
    setBusy(false)
    if (!res.ok) { onToast({ msg: d.error || 'Failed', type: 'error' }); return }
    onChanged(d.accountHold); setOpen(false); setReason('')
    onToast({ msg: body.active ? 'Account put on hold' : 'Hold released', type: 'success' })
  }

  return (
    <div className={`rounded-xl border shadow-sm p-4 ${hold ? 'bg-amber-50 border-amber-200' : 'bg-white border-gray-100'}`}>
      <div className="flex items-center justify-between">
        <p className="text-sm font-semibold text-gray-800 flex items-center gap-2"><PauseCircle className="w-4 h-4" /> Account hold</p>
        {hold ? <span className="text-[11px] font-bold uppercase bg-amber-500 text-white px-2 py-0.5 rounded">On hold</span>
          : <span className="text-[11px] font-bold uppercase bg-green-100 text-green-700 px-2 py-0.5 rounded">Active</span>}
      </div>
      {hold ? (
        <div className="mt-2 text-sm">
          <p className="font-medium text-amber-800">{KIND_LABEL[hold.kind] || hold.kind}</p>
          {hold.reason && <p className="text-amber-700 text-xs mt-0.5">{hold.reason}</p>}
          {hold.at && <p className="text-[11px] text-amber-600 mt-1">Since {new Date(hold.at).toLocaleString('en-IN')} {hold.by ? `· by ${hold.by}` : ''}</p>}
          <p className="text-xs text-gray-600 mt-2">{isDriver ? 'Cannot go online or accept rides.' : 'Cannot book rides.'}</p>
          <button type="button" disabled={busy} onClick={() => send({ active: false })}
            className="mt-3 w-full flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-medium bg-green-600 text-white hover:bg-green-700 disabled:opacity-60">
            <PlayCircle className="w-4 h-4" /> Release hold
          </button>
        </div>
      ) : (
        <>
          {walletNote && <p className="text-xs text-rose-600 mt-2">{walletNote}</p>}
          {!open ? (
            <button type="button" onClick={() => setOpen(true)}
              className="mt-3 w-full flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-medium bg-amber-50 text-amber-700 border border-amber-200 hover:bg-amber-100">
              <PauseCircle className="w-4 h-4" /> Put on hold
            </button>
          ) : (
            <div className="mt-3 space-y-2">
              <select className={`${input} bg-white`} value={kind} onChange={e => setKind(e.target.value)} aria-label="Hold reason type">
                {isDriver && <option value="face">Wrong face scan</option>}
                <option value="wallet">Wallet mis-transaction</option>
                <option value="manual">Other admin reason</option>
              </select>
              <textarea className={input} rows={2} placeholder="Reason (shown to the person)" value={reason} onChange={e => setReason(e.target.value)} />
              <div className="flex gap-2">
                <button type="button" onClick={() => setOpen(false)} className="flex-1 py-2 border rounded-lg text-sm">Cancel</button>
                <button type="button" disabled={busy || !reason.trim()} onClick={() => send({ active: true, kind, reason })}
                  className="flex-1 py-2 bg-amber-500 text-white rounded-lg text-sm font-semibold disabled:opacity-60">Hold</button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  )
}

/** Driver zone: change it (manual) and switch automatic zone on/off. */
export function ZoneCard({ driver, onSaved, onToast }: {
  driver: any
  onSaved: (d: any) => void
  onToast: (t: { msg: string; type: 'success' | 'error' }) => void
}) {
  const [zones, setZones] = useState<any[]>([])
  const [zoneId, setZoneId] = useState(driver?.zoneId || '')
  const [busy, setBusy] = useState(false)
  useEffect(() => { fetch('/api/zones').then(r => r.json()).then(d => setZones(d.zones || [])).catch(() => {}) }, [])
  useEffect(() => { setZoneId(driver?.zoneId || '') }, [driver?.zoneId])
  const put = async (body: any, msg: string) => {
    setBusy(true)
    const res = await fetch(`/api/drivers/${driver._id}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    const d = await res.json().catch(() => ({}))
    setBusy(false)
    if (!res.ok) { onToast({ msg: d.error || 'Failed', type: 'error' }); return }
    onSaved(d); onToast({ msg, type: 'success' })
  }
  const history = [...(driver?.zoneHistory || [])].reverse().slice(0, 5)
  return (
    <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4">
      <p className="text-sm font-semibold text-gray-800 flex items-center gap-2 mb-3"><MapPin className="w-4 h-4" /> Zone</p>
      <div className="flex gap-2">
        <select aria-label="Driver zone" className={`${input} bg-white`} value={zoneId} onChange={e => setZoneId(e.target.value)}>
          <option value="">— No zone —</option>
          {zones.map(z => <option key={z._id} value={z._id}>{z.name}{z.isActive === false ? ' (inactive)' : ''}</option>)}
        </select>
        <button type="button" disabled={busy || !zoneId || zoneId === driver?.zoneId}
          onClick={() => put({ zoneId }, 'Zone changed')}
          className="px-3 py-2 bg-primary text-white rounded-lg text-sm font-semibold disabled:opacity-50">Change</button>
      </div>
      <label className="flex items-center justify-between gap-2 mt-3 text-sm text-gray-700">
        <span>Automatic zone (follows the driver&apos;s location)</span>
        <input type="checkbox" checked={!!driver?.zoneAuto} disabled={busy}
          onChange={e => put({ zoneAuto: e.target.checked }, e.target.checked ? 'Automatic zone on' : 'Automatic zone off')} />
      </label>
      {history.length > 0 && (
        <div className="mt-3 border-t pt-2">
          <p className="text-xs text-gray-500 flex items-center gap-1 mb-1"><History className="w-3 h-3" /> Zone history</p>
          {history.map((h: any, i: number) => (
            <p key={i} className="text-xs text-gray-600">
              {h.fromName || '—'} → <b>{h.toName}</b> · {String(h.by || '').startsWith('auto') ? 'automatic' : String(h.by || '').startsWith('request') ? 'driver request' : 'admin'} · {h.at ? new Date(h.at).toLocaleDateString('en-IN') : ''}
            </p>
          ))}
        </div>
      )}
    </div>
  )
}
