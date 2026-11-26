'use client'
import { useCallback, useEffect, useState } from 'react'
import { Search, Eye } from 'lucide-react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { zoneFetch, useZoneSession } from '@/components/zone-shell'

const STATUS_TABS = ['', 'pending', 'approved', 'blocked', 'rejected']

export default function ZoneDrivers() {
  const session = useZoneSession()
  const canManage = !!session?.features.includes('drivers') && !session?.readOnly
  const [drivers, setDrivers] = useState<any[] | null>(null)
  const [q, setQ] = useState('')
  const [tab, setTab] = useState('')
  const [open, setOpen] = useState<any>(null)
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  // Paged on the server (true total); search on Enter.
  const [page, setPage] = useState(1)
  const [appliedQ, setAppliedQ] = useState('')
  const [meta, setMeta] = useState<{ total: number; pages: number; counts: Record<string, number> }>({ total: 0, pages: 1, counts: {} })

  const load = useCallback(() => {
    const p = new URLSearchParams({ page: String(page) })
    if (tab) p.set('status', tab)
    if (appliedQ) p.set('q', appliedQ)
    zoneFetch(`/api/zone-admin/drivers?${p}`).then(r => r.json())
      .then(d => { setDrivers(d.drivers || []); setMeta({ total: d.total || 0, pages: d.pages || 1, counts: d.counts || {} }) })
      .catch(() => {})
  }, [page, tab, appliedQ])
  useEffect(() => { load() }, [load])

  const review = async (id: string) => {
    setReason('')
    const r = await zoneFetch(`/api/zone-admin/drivers/${id}`)
    const d = await r.json()
    if (!r.ok) { setToast({ msg: d.error || 'Could not open', type: 'error' }); return }
    setOpen(d.driver)
  }

  const act = async (action: string) => {
    if (action === 'reject' && !reason.trim()) { setToast({ msg: 'Write the reason for rejecting', type: 'error' }); return }
    setBusy(true)
    try {
      const r = await zoneFetch(`/api/zone-admin/drivers/${open._id}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action, reason }),
      })
      const d = await r.json()
      if (!r.ok) { setToast({ msg: d.error || 'Failed', type: 'error' }); return }
      setToast({ msg: `Driver ${d.status}`, type: 'success' }); setOpen(null); load()
    } finally { setBusy(false) }
  }

  const shown = drivers || []

  return (
    <div>
      <Header title="Drivers" />
      <div className="p-6">
        <div className="bg-white rounded shadow-sm">
          <div className="p-4 border-b border-[#e9ebec] flex flex-wrap gap-3 items-center justify-between">
            <div className="flex flex-wrap gap-2">
              {STATUS_TABS.map(s => (
                <button key={s || 'all'} type="button" onClick={() => { setTab(s); setPage(1) }}
                  className={`px-3 py-1.5 rounded text-[13px] capitalize ${tab === s ? 'bg-primary text-white' : 'bg-[#f3f6f9] text-[#495057]'}`}>
                  {s || 'All'}{s ? ` (${meta.counts[s] || 0})` : ''}
                </button>
              ))}
            </div>
            <div className="flex items-center gap-2 border border-[#ced4da] rounded px-3 py-2 w-full max-w-xs">
              <Search className="w-4 h-4 text-gray-400" />
              <input value={q} onChange={e => setQ(e.target.value)} aria-label="Search drivers"
                onKeyDown={e => { if (e.key === 'Enter') { setAppliedQ(q.trim()); setPage(1) } }}
                onBlur={() => { if (q.trim() !== appliedQ) { setAppliedQ(q.trim()); setPage(1) } }}
                placeholder="Search name, phone or vehicle (Enter)" className="outline-none text-[13px] w-full" />
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-[13px]">
              <thead><tr>{['Driver', 'Phone', 'Vehicle', 'Rating', 'Trips', 'Online', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {!drivers ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">Loading…</td></tr> :
                  shown.length === 0 ? <tr><td colSpan={8} className="text-center py-10 text-gray-400">No drivers</td></tr> :
                  shown.map(d => (
                    <tr key={d._id}>
                      <td className="px-4 py-3 font-medium text-[#495057]">{d.name || '—'}</td>
                      <td className="px-4 py-3">{d.phone}</td>
                      <td className="px-4 py-3">{d.selectedVehicleTypeName || '—'}{d.vehicleNumber ? ` · ${d.vehicleNumber}` : ''}</td>
                      <td className="px-4 py-3">{d.rating ?? '—'}</td>
                      <td className="px-4 py-3">{d.totalRides ?? 0}</td>
                      <td className="px-4 py-3">{d.isOnline ? <span className="text-green-600 font-medium">● Online</span> : <span className="text-gray-400">Offline</span>}</td>
                      <td className="px-4 py-3"><Badge status={d.status || 'pending'} /></td>
                      <td className="px-4 py-3 text-right">
                        {session?.features.includes('drivers') && (
                          <button type="button" onClick={() => review(d._id)} className="inline-flex items-center gap-1 text-primary"><Eye className="w-4 h-4" /> Review</button>
                        )}
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
          <div className="p-4 flex items-center justify-between gap-2 text-[13px]">
            <span className="text-gray-500">{meta.total} driver{meta.total === 1 ? '' : 's'}</span>
            <div className="flex items-center gap-2">
              <button type="button" disabled={page <= 1} onClick={() => setPage(p => p - 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Prev</button>
              <span>Page {page} of {meta.pages}</span>
              <button type="button" disabled={page >= meta.pages} onClick={() => setPage(p => p + 1)} className="px-3 py-1.5 border rounded disabled:opacity-40">Next</button>
            </div>
          </div>
        </div>
        <p className="text-xs text-gray-500 mt-3">
          {session?.features.includes('drivers') ? 'You can approve, reject, block and unblock drivers in your zone. Wallet and deletion are handled by Gora.' : 'Driver approval is handled by Gora on your plan.'}
        </p>
      </div>

      {open && (
        <Modal title={open.name || 'Driver'} onClose={() => setOpen(null)} size="lg">
          <div className="space-y-4 text-[13px]">
            <div className="grid grid-cols-2 gap-2">
              <p><span className="text-gray-500">Phone:</span> {open.phone}</p>
              <p><span className="text-gray-500">Status:</span> <Badge status={open.status} /></p>
              <p><span className="text-gray-500">Vehicle:</span> {open.selectedVehicleTypeName} {open.vehicleModel ? `· ${open.vehicleModel}` : ''}</p>
              <p><span className="text-gray-500">Number:</span> {open.vehicleNumber || '—'}</p>
            </div>
            {open.rejectionReason && <p className="text-red-600">Earlier rejected: {open.rejectionReason}</p>}
            <div>
              <p className="font-semibold mb-2">Documents</p>
              {open.documents.length === 0 ? <p className="text-gray-400">No documents uploaded</p> : (
                <div className="grid sm:grid-cols-3 gap-3">
                  {open.documents.map((doc: any, i: number) => (
                    <div key={i} className="border rounded p-2">
                      <p className="uppercase text-[11px] font-semibold text-gray-500 mb-1">{doc.type} · {doc.status || 'pending'}</p>
                      {[doc.frontUrl, doc.backUrl].filter(Boolean).map((u: string) => (
                        <a key={u} href={u} target="_blank" rel="noreferrer">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img src={u} alt={doc.type} className="w-full h-24 object-cover rounded mb-1" />
                        </a>
                      ))}
                    </div>
                  ))}
                </div>
              )}
            </div>
            {canManage ? (
              <div className="border-t pt-4 space-y-3">
                <input value={reason} onChange={e => setReason(e.target.value)} placeholder="Reason (needed to reject)"
                  className="w-full border border-[#ced4da] rounded px-3 py-2 text-[13px]" />
                <div className="flex flex-wrap gap-2 justify-end">
                  {open.status !== 'approved' && open.status !== 'blocked' && <button type="button" disabled={busy} onClick={() => act('approve')} className="px-4 py-2 rounded bg-green-600 text-white">Approve</button>}
                  {open.status !== 'rejected' && open.status !== 'blocked' && <button type="button" disabled={busy} onClick={() => act('reject')} className="px-4 py-2 rounded bg-red-500 text-white">Reject</button>}
                  {open.status === 'approved' && <button type="button" disabled={busy} onClick={() => act('block')} className="px-4 py-2 rounded bg-gray-700 text-white">Block</button>}
                  {open.status === 'blocked' && <button type="button" disabled={busy} onClick={() => act('unblock')} className="px-4 py-2 rounded bg-primary text-white">Unblock</button>}
                </div>
              </div>
            ) : session?.readOnly && <p className="text-red-600">Read-only until your subscription is renewed.</p>}
          </div>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
