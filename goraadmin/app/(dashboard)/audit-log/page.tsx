'use client'
import { Fragment, useCallback, useEffect, useState } from 'react'
import { Header } from '@/components/header'

// Who changed what in the dashboard (models/AdminAudit). Every non-GET admin
// API call is logged; money, pricing and account actions carry a name, the
// record they touched and the values sent (secrets removed).
export default function AuditLogPage() {
  const [rows, setRows] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [actions, setActions] = useState<string[]>([])
  const [page, setPage] = useState(1)
  const [f, setF] = useState({ action: '', email: '', q: '', from: '', to: '', generic: '1' })
  const [loading, setLoading] = useState(true)
  const [open, setOpen] = useState<string | null>(null)
  const limit = 50

  const load = useCallback(() => {
    setLoading(true)
    const p = new URLSearchParams({ page: String(page), limit: String(limit) })
    for (const [k, v] of Object.entries(f)) if (v) p.set(k, v)
    fetch(`/api/audit-log?${p}`).then(r => r.json()).then(d => {
      setRows(d.rows || []); setTotal(d.total || 0); setActions(d.actions || []); setLoading(false)
    }).catch(() => setLoading(false))
  }, [page, f])
  useEffect(() => { load() }, [load])

  const set = (k: string, v: string) => { setPage(1); setF({ ...f, [k]: v }) }
  const pages = Math.max(1, Math.ceil(total / limit))
  const inp = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'
  const fmt = (d: string) => new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'medium' })

  return (
    <div>
      <Header title="Audit Log" />
      <div className="p-6 space-y-4">
        <div className="bg-white rounded-xl border p-4 flex flex-wrap gap-3 items-end">
          <div>
            <label className="block text-xs text-gray-500 mb-1">Action</label>
            <select className={inp} value={f.action} onChange={e => set('action', e.target.value)} aria-label="Action">
              <option value="">All actions</option>
              {actions.map(a => <option key={a} value={a}>{a}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Admin email</label>
            <input className={inp} value={f.email} onChange={e => set('email', e.target.value)} placeholder="name@…" aria-label="Admin email" />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Path / record / summary</label>
            <input className={inp} value={f.q} onChange={e => set('q', e.target.value)} placeholder="driver id, /api/promos …" aria-label="Search" />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">From</label>
            <input type="date" className={inp} value={f.from} onChange={e => set('from', e.target.value)} aria-label="From date" />
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">To</label>
            <input type="date" className={inp} value={f.to} onChange={e => set('to', e.target.value)} aria-label="To date" />
          </div>
          <label className="flex items-center gap-2 text-sm pb-2">
            <input type="checkbox" checked={f.generic === '1'} onChange={e => set('generic', e.target.checked ? '1' : '0')} /> Show plain API calls
          </label>
        </div>

        <div className="bg-white rounded-xl border overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-600 text-left">
              <tr>
                <th className="px-4 py-3">When (IST)</th><th className="px-4 py-3">Admin</th><th className="px-4 py-3">Action</th>
                <th className="px-4 py-3">Record</th><th className="px-4 py-3">Summary</th><th className="px-4 py-3">Request</th><th className="px-4 py-3">IP</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">Loading…</td></tr>
              ) : rows.length === 0 ? (
                <tr><td colSpan={7} className="px-4 py-8 text-center text-gray-400">No entries</td></tr>
              ) : rows.map(r => (
                <Fragment key={r._id}>
                  <tr className="border-t hover:bg-gray-50 cursor-pointer" onClick={() => setOpen(open === r._id ? null : r._id)}>
                    <td className="px-4 py-2 whitespace-nowrap">{fmt(r.at)}</td>
                    <td className="px-4 py-2">{r.email || '—'}</td>
                    <td className="px-4 py-2 font-mono text-xs">{r.action}</td>
                    <td className="px-4 py-2 font-mono text-xs">{r.target || '—'}</td>
                    <td className="px-4 py-2">{r.summary || ''}</td>
                    <td className="px-4 py-2 font-mono text-xs whitespace-nowrap">{r.method} {r.path}</td>
                    <td className="px-4 py-2 text-xs text-gray-500">{r.ip}</td>
                  </tr>
                  {open === r._id && r.details !== undefined && (
                    <tr className="bg-gray-50">
                      <td colSpan={7} className="px-4 py-2"><pre className="text-xs whitespace-pre-wrap break-all">{JSON.stringify(r.details, null, 2)}</pre></td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        </div>

        <div className="flex items-center justify-between text-sm text-gray-600">
          <span>{total} {total === 1 ? 'entry' : 'entries'}</span>
          <div className="flex items-center gap-2">
            <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
            <span>Page {page} of {pages}</span>
            <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</button>
          </div>
        </div>
      </div>
    </div>
  )
}
