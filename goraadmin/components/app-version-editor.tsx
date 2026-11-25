'use client'
import { useEffect, useState } from 'react'

// Force-update settings of one app (AppConfig.version), saved on its own so it
// can sit on any settings page. The apps read it from GET /api/app-config?app=…
export function AppVersionEditor({ app }: { app: 'user' | 'driver' }) {
  const [v, setV] = useState<any>(null)
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  useEffect(() => {
    fetch(`/api/app-config?app=${app}`).then(r => r.json()).then(r => setV(r.config?.version || {})).catch(() => setV({}))
  }, [app])
  async function save() {
    setBusy(true); setMsg('')
    try {
      const r = await fetch('/api/app-config', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ app, version: v }) }).then(r => r.json())
      if (r.config) { setV(r.config.version || {}); setMsg('Saved ✓') } else setMsg(r.error || 'Failed')
    } catch (e: any) { setMsg(e.message) }
    setBusy(false)
  }
  if (!v) return <div className="text-sm text-gray-500">Loading…</div>
  const inp = 'w-full border border-gray-300 rounded px-2 py-1.5 text-sm'
  const f = (k: string, label: string, ph: string) => (
    <div><label className="block text-xs font-medium text-gray-600 mb-1">{label}</label>
      <input className={inp} title={label} placeholder={ph} value={v[k] || ''} onChange={e => setV({ ...v, [k]: e.target.value })} /></div>
  )
  return (
    <div className="bg-white border rounded-xl p-4 space-y-3 max-w-md">
      <p className="text-xs text-gray-500">Apps below the minimum version must update before they can be used. With &quot;Force update&quot; on, anyone below the latest version must update.</p>
      {f('latestVersion', 'Latest version', '1.4.0')}
      {f('minVersion', 'Minimum supported version', '1.3.0')}
      <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!v.forceUpdate} onChange={e => setV({ ...v, forceUpdate: e.target.checked })} /> Force update to the latest version</label>
      {f('message', 'Message', 'A new version is available')}
      {f('storeUrl', 'Store link (https://)', 'https://play.google.com/store/apps/details?id=…')}
      <div className="flex items-center justify-end gap-3 pt-2 border-t">
        {msg && <span className="text-sm font-semibold text-green-600">{msg}</span>}
        <button type="button" onClick={save} disabled={busy} className="bg-[#405189] text-white px-6 py-2 rounded-lg text-sm font-semibold disabled:opacity-50">Save</button>
      </div>
    </div>
  )
}
