'use client'
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Building2 } from 'lucide-react'
import { Modal } from '@/components/ui/modal'

// Franchise mode in the super admin panel: read it, switch it (with a
// confirmation), and tell other parts of the page when it changes.

const EVENT = 'franchise-mode-changed'

/** null while loading. */
export function useFranchiseMode() {
  const [enabled, setEnabled] = useState<boolean | null>(null)
  const [meta, setMeta] = useState<{ changedAt: string | null; changedBy: string }>({ changedAt: null, changedBy: '' })
  const load = useCallback(() => {
    fetch('/api/settings/franchise').then(r => r.json()).then(d => {
      setEnabled(d.enabled === true); setMeta({ changedAt: d.changedAt || null, changedBy: d.changedBy || '' })
    }).catch(() => setEnabled(false))
  }, [])
  useEffect(() => {
    load()
    const on = () => load()
    window.addEventListener(EVENT, on)
    return () => window.removeEventListener(EVENT, on)
  }, [load])
  return { enabled, meta }
}

/** The switch, for Settings → General. */
export function FranchiseModeCard() {
  const { enabled, meta } = useFranchiseMode()
  const [confirm, setConfirm] = useState<boolean | null>(null)   // the value being confirmed
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const apply = async () => {
    if (confirm === null) return
    setBusy(true); setErr('')
    try {
      const r = await fetch('/api/settings/franchise', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ enabled: confirm }) })
      const d = await r.json()
      if (!r.ok) { setErr(d.error || 'Could not change'); return }
      setConfirm(null)
      window.dispatchEvent(new Event(EVENT))
    } finally { setBusy(false) }
  }

  return (
    <div className="bg-white rounded shadow-sm p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="flex gap-3">
          <div className="w-10 h-10 rounded bg-blue-50 flex items-center justify-center flex-shrink-0"><Building2 className="w-5 h-5 text-blue-600" /></div>
          <div>
            <h5 className="font-semibold text-[15px] text-[#495057]">Franchise Mode</h5>
            <p className="text-[13px] text-gray-500 mt-0.5 max-w-xl">
              On: zone admins sign in to their zone panel on a subscription, with their zone promo codes and helplines.
              Off: the app runs as before franchises — their data is kept, hidden and inactive.
            </p>
            {meta.changedAt && <p className="text-[12px] text-gray-400 mt-1">Last changed {new Date(meta.changedAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })}{meta.changedBy ? ` by ${meta.changedBy}` : ''}</p>}
          </div>
        </div>
        <button type="button" role="switch" aria-checked={!!enabled} aria-label="Franchise mode" disabled={enabled === null}
          onClick={() => setConfirm(!enabled)}
          className={`relative inline-flex h-7 w-12 flex-shrink-0 items-center rounded-full transition-colors ${enabled ? 'bg-green-600' : 'bg-gray-300'} disabled:opacity-50`}>
          <span className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${enabled ? 'translate-x-6' : 'translate-x-1'}`} />
        </button>
      </div>

      {confirm !== null && (
        <Modal title={confirm ? 'Turn franchise mode ON?' : 'Turn franchise mode OFF?'} onClose={() => !busy && setConfirm(null)} size="sm">
          <div className="space-y-3 text-[13px] text-[#495057]">
            {confirm ? (
              <ul className="list-disc pl-5 space-y-1">
                <li>Zone admins with an active subscription can sign in to their zone panel.</li>
                <li>The Franchise menu (Zone Admins, Plans, Report) appears here.</li>
                <li>Zone admin promo codes and zone helplines start working.</li>
              </ul>
            ) : (
              <ul className="list-disc pl-5 space-y-1">
                <li>Every zone admin and staff member is signed out of the zone panel at once.</li>
                <li>Their promo codes stop working and riders see Gora&apos;s support number.</li>
                <li>Nothing is deleted. Fares a zone admin already changed stay as they are.</li>
                <li>Turning it on again brings everything back as it was.</li>
              </ul>
            )}
            {err && <p className="text-red-600">{err}</p>}
            <div className="flex justify-end gap-2 pt-2">
              <button type="button" disabled={busy} onClick={() => setConfirm(null)} className="px-4 py-2 rounded border">Cancel</button>
              <button type="button" disabled={busy} onClick={apply}
                className={`px-4 py-2 rounded text-white ${confirm ? 'bg-green-600' : 'bg-red-500'} disabled:opacity-60`}>
                {busy ? 'Saving…' : confirm ? 'Yes, turn ON' : 'Yes, turn OFF'}
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  )
}

/** Shown on franchise pages opened by link while the mode is off. */
export function FranchiseOffBanner() {
  const { enabled } = useFranchiseMode()
  if (enabled !== false) return null
  return (
    <div className="bg-yellow-50 border border-yellow-200 text-yellow-800 rounded px-4 py-3 text-[13px]">
      Franchise mode is OFF — zone admins cannot sign in and their promo codes are inactive. Turn it on in{' '}
      <Link href="/settings/general" className="font-semibold underline">Settings → General</Link>.
    </div>
  )
}
