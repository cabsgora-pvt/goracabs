'use client'
import { useCallback, useEffect, useState } from 'react'
import { AlertTriangle } from 'lucide-react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { zoneFetch, useZoneSession } from '@/components/zone-shell'

export default function ZoneSupport() {
  const session = useZoneSession()
  const canAct = !session?.readOnly
  const [d, setD] = useState<any>(null)
  const [tab, setTab] = useState<'sos' | 'tickets'>('sos')
  const [open, setOpen] = useState<any>(null)
  const [reply, setReply] = useState('')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const load = useCallback(() => { zoneFetch('/api/zone-admin/support').then(r => r.json()).then(setD).catch(() => {}) }, [])
  useEffect(() => { load() }, [load])

  const patch = async (body: any, ok: string) => {
    const r = await zoneFetch('/api/zone-admin/support', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    const x = await r.json()
    if (!r.ok) { setToast({ msg: x.error || 'Failed', type: 'error' }); return null }
    setToast({ msg: ok, type: 'success' }); load(); return x
  }

  const activeSos = (d?.sos || []).filter((s: any) => s.status === 'active').length

  return (
    <div>
      <Header title="Support & SOS" />
      <div className="p-6 space-y-4">
        {activeSos > 0 && (
          <div className="bg-red-50 border border-red-200 text-red-700 rounded px-4 py-3 text-[13px] flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" /> {activeSos} SOS alert{activeSos > 1 ? 's are' : ' is'} still active in your zone. Call them now.
          </div>
        )}
        <div className="flex gap-2">
          {(['sos', 'tickets'] as const).map(t => (
            <button key={t} type="button" onClick={() => setTab(t)}
              className={`px-4 py-2 rounded text-[13px] ${tab === t ? 'bg-primary text-white' : 'bg-white text-[#495057] shadow-sm'}`}>
              {t === 'sos' ? `SOS alerts (${d?.sos?.length ?? '…'})` : `Tickets (${d?.tickets?.length ?? '…'})`}
            </button>
          ))}
        </div>
        <div className="bg-white rounded shadow-sm overflow-x-auto">
          {tab === 'sos' ? (
            <table className="w-full text-[13px]">
              <thead><tr>{['When', 'Who', 'Phone', 'Where', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {!d ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">Loading…</td></tr> : d.sos.length === 0 ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">No SOS alerts</td></tr> :
                  d.sos.map((s: any) => (
                    <tr key={s._id} className={s.status === 'active' ? 'bg-red-50/50' : ''}>
                      <td className="px-4 py-3 whitespace-nowrap">{new Date(s.createdAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</td>
                      <td className="px-4 py-3">{s.name || '—'} <span className="text-gray-400">({s.triggeredBy})</span></td>
                      <td className="px-4 py-3"><a href={`tel:${s.phone}`} className="text-primary">{s.phone}</a></td>
                      <td className="px-4 py-3 max-w-[260px] truncate">
                        {s.lat != null ? <a className="text-primary" target="_blank" rel="noreferrer" href={`https://maps.google.com/?q=${s.lat},${s.lng}`}>{s.address || 'Open map'}</a> : (s.address || '—')}
                      </td>
                      <td className="px-4 py-3"><Badge status={s.status === 'active' ? 'high' : 'resolved'} /></td>
                      <td className="px-4 py-3 text-right">
                        {canAct && s.status === 'active' && <button type="button" onClick={() => patch({ kind: 'sos', id: s._id, status: 'resolved' }, 'SOS resolved')} className="px-3 py-1.5 rounded bg-green-600 text-white text-[12.5px]">Mark resolved</button>}
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          ) : (
            <table className="w-full text-[13px]">
              <thead><tr>{['Date', 'From', 'Subject', 'Priority', 'Status', ''].map(h => <th key={h} className="text-left px-4 py-3">{h}</th>)}</tr></thead>
              <tbody className="divide-y">
                {!d ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">Loading…</td></tr> : d.tickets.length === 0 ? <tr><td colSpan={6} className="text-center py-8 text-gray-400">No tickets</td></tr> :
                  d.tickets.map((t: any) => (
                    <tr key={t._id}>
                      <td className="px-4 py-3 whitespace-nowrap">{new Date(t.createdAt).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}</td>
                      <td className="px-4 py-3">{t.userName || '—'} <span className="text-gray-400">({t.role})</span></td>
                      <td className="px-4 py-3 max-w-[300px] truncate">{t.subject}</td>
                      <td className="px-4 py-3"><Badge status={t.priority} /></td>
                      <td className="px-4 py-3"><Badge status={t.status === 'in_progress' ? 'processing' : t.status} /></td>
                      <td className="px-4 py-3 text-right"><button type="button" onClick={() => { setOpen(t); setReply('') }} className="text-primary">Open</button></td>
                    </tr>
                  ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {open && (
        <Modal title={open.subject || 'Ticket'} onClose={() => setOpen(null)} size="lg">
          <div className="space-y-3 text-[13px]">
            <div className="max-h-72 overflow-y-auto space-y-2">
              {(open.messages || []).map((m: any, i: number) => (
                <div key={i} className={`rounded px-3 py-2 ${m.sender === 'admin' ? 'bg-blue-50 ml-8' : 'bg-gray-50 mr-8'}`}>
                  <p className="text-[11px] text-gray-500 mb-0.5">{m.sender} · {new Date(m.sentAt).toLocaleString('en-IN', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}</p>
                  <p>{m.message}</p>
                </div>
              ))}
            </div>
            {canAct && (
              <>
                <textarea rows={3} value={reply} onChange={e => setReply(e.target.value)} placeholder="Write a reply…" className="w-full border border-[#ced4da] rounded px-3 py-2" />
                <div className="flex flex-wrap gap-2 justify-end">
                  {['in_progress', 'resolved', 'closed'].map(s => (
                    <button key={s} type="button" onClick={async () => { const x = await patch({ kind: 'ticket', id: open._id, status: s, reply }, 'Ticket updated'); if (x) setOpen(null) }}
                      className={`px-3 py-2 rounded text-[12.5px] ${s === 'resolved' ? 'bg-green-600 text-white' : 'border'}`}>
                      {reply ? 'Reply & ' : ''}{s.replace('_', ' ')}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
