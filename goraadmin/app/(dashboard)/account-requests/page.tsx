'use client'
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Trash2, MapPin, Check, X } from 'lucide-react'

const TABS = [
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'all', label: 'All' },
]
const STATUS_CLS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800', approved: 'bg-green-100 text-green-700',
  rejected: 'bg-red-100 text-red-700', cancelled: 'bg-gray-100 text-gray-600',
}

// Requests riders and drivers make from the apps that the admin decides:
// account deletion (with the reason they gave) and driver zone changes.
export default function AccountRequestsPage() {
  const [status, setStatus] = useState('pending')
  const [kind, setKind] = useState('')
  const [rows, setRows] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [act, setAct] = useState<{ r: any; action: 'approve' | 'reject' } | null>(null)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => {
    setLoading(true)
    const q = new URLSearchParams({ status, ...(kind ? { kind } : {}) })
    fetch(`/api/account-requests?${q}`).then(r => r.json()).then(d => { setRows(d.requests || []); setLoading(false) }).catch(() => setLoading(false))
  }, [status, kind])
  useEffect(() => { load() }, [load])

  const decide = async () => {
    if (!act) return
    setBusy(true)
    const res = await fetch(`/api/account-requests/${act.r._id}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: act.action, note }),
    })
    const d = await res.json().catch(() => ({}))
    setBusy(false)
    if (!res.ok) { setToast({ msg: d.error || 'Failed', type: 'error' }); return }
    setToast({ msg: act.action === 'approve' ? 'Request approved' : 'Request rejected', type: 'success' })
    setAct(null); setNote(''); load()
  }

  const who = (r: any) => r.userType === 'driver' ? `/drivers/${r.userId}` : `/users/${r.userId}`

  return (
    <div>
      <Header title="Account Requests" />
      <div className="p-6 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex gap-1 bg-white rounded-lg border p-1">
            {TABS.map(t => (
              <button key={t.key} type="button" onClick={() => setStatus(t.key)}
                className={`px-3 py-1.5 rounded-md text-sm ${status === t.key ? 'bg-primary text-white' : 'text-gray-600 hover:bg-gray-50'}`}>{t.label}</button>
            ))}
          </div>
          <select aria-label="Request type" value={kind} onChange={e => setKind(e.target.value)} className="border rounded-lg px-3 py-2 text-sm bg-white">
            <option value="">All types</option>
            <option value="delete">Account deletion</option>
            <option value="zone_change">Zone change</option>
          </select>
        </div>

        <div className="bg-white rounded shadow-sm overflow-x-auto">
          <table className="w-full text-[13px]">
            <thead><tr>{['Date', 'Who', 'Request', 'Reason / details', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
            <tbody className="divide-y">
              {loading ? <tr><td colSpan={6} className="text-center py-10 text-gray-400">Loading…</td></tr>
                : rows.length === 0 ? <tr><td colSpan={6} className="text-center py-10 text-gray-400">No requests</td></tr>
                : rows.map(r => (
                  <tr key={r._id} className="align-top">
                    <td className="px-4 py-3 whitespace-nowrap text-gray-500">{new Date(r.createdAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                    <td className="px-4 py-3">
                      <Link href={who(r)} className="font-medium text-primary hover:underline">{r.name || '—'}</Link>
                      <p className="text-xs text-gray-500">{r.userType === 'driver' ? 'Driver' : 'Rider'} · {r.phone}</p>
                    </td>
                    <td className="px-4 py-3">
                      {r.kind === 'delete'
                        ? <span className="inline-flex items-center gap-1 text-red-600 font-medium"><Trash2 className="w-3.5 h-3.5" />Delete account</span>
                        : <span className="inline-flex items-center gap-1 text-blue-700 font-medium"><MapPin className="w-3.5 h-3.5" />Zone change</span>}
                    </td>
                    <td className="px-4 py-3 max-w-sm">
                      {r.kind === 'zone_change'
                        ? <p>{r.fromZoneName || 'No zone'} → <b>{r.toZoneName}</b></p>
                        : <p className="font-medium">{r.reason}</p>}
                      {r.note && <p className="text-xs text-gray-500 mt-0.5">“{r.note}”</p>}
                      {r.adminNote && <p className="text-xs text-gray-400 mt-1">Admin: {r.adminNote}</p>}
                    </td>
                    <td className="px-4 py-3"><span className={`px-2 py-0.5 rounded text-[11px] font-semibold uppercase ${STATUS_CLS[r.status] || ''}`}>{r.status}</span>
                      {r.handledAt && <p className="text-[11px] text-gray-400 mt-1">{new Date(r.handledAt).toLocaleDateString('en-IN')}</p>}</td>
                    <td className="px-4 py-3 text-right whitespace-nowrap">
                      {r.status === 'pending' && (
                        <div className="flex gap-2 justify-end">
                          <button type="button" onClick={() => setAct({ r, action: 'approve' })} className="inline-flex items-center gap-1 px-3 py-1.5 rounded bg-green-600 text-white text-xs font-semibold"><Check className="w-3.5 h-3.5" />Approve</button>
                          <button type="button" onClick={() => setAct({ r, action: 'reject' })} className="inline-flex items-center gap-1 px-3 py-1.5 rounded bg-red-50 text-red-600 border border-red-200 text-xs font-semibold"><X className="w-3.5 h-3.5" />Reject</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>

      {act && (
        <Modal title={act.action === 'approve' ? 'Approve request' : 'Reject request'} onClose={() => setAct(null)}>
          <div className="space-y-3 text-sm">
            {act.action === 'approve' && act.r.kind === 'delete' && (
              <p className="p-3 rounded bg-red-50 text-red-700">This closes <b>{act.r.name}</b>&apos;s {act.r.userType} account: their name, phone and email are removed and they are signed out. Ride and payment history is kept. This cannot be undone.</p>
            )}
            {act.action === 'approve' && act.r.kind === 'zone_change' && (
              <p className="p-3 rounded bg-blue-50 text-blue-800">{act.r.name} will be moved from {act.r.fromZoneName || 'no zone'} to <b>{act.r.toZoneName}</b>.</p>
            )}
            <label className="block">
              <span className="text-xs text-gray-500">Note {act.action === 'reject' ? '(shown to them)' : '(optional)'}</span>
              <textarea className="w-full border rounded-lg px-3 py-2 mt-1" rows={2} value={note} onChange={e => setNote(e.target.value)} />
            </label>
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setAct(null)} className="px-4 py-2 border rounded-lg">Cancel</button>
              <button type="button" disabled={busy} onClick={decide}
                className={`px-4 py-2 rounded-lg text-white font-semibold disabled:opacity-60 ${act.action === 'approve' ? 'bg-green-600' : 'bg-red-600'}`}>
                {busy ? 'Saving…' : act.action === 'approve' ? 'Approve' : 'Reject'}
              </button>
            </div>
          </div>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
