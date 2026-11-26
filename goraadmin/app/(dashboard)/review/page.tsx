'use client'
import { useCallback, useEffect, useState } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { RideActions } from '@/components/rides/ride-actions'

// Everything that waits for an admin, in one place (GET /api/review):
// flagged rides, COD a driver still owes, refunds that could not run on their
// own, and withdrawals to a recently changed bank account. Actions that touch
// money ask for the admin password (components/settings-password-guard) and
// are written to the audit log by the server.
type Tab = 'rides' | 'cod' | 'refunds' | 'withdrawals'
const TABS: { key: Tab; label: string }[] = [
  { key: 'rides', label: 'Flagged rides' },
  { key: 'cod', label: 'COD pending remittance' },
  { key: 'refunds', label: 'Refund problems' },
  { key: 'withdrawals', label: 'Withdrawals (bank changed)' },
]

type Act = { kind: 'resolve' | 'cod_settled' | 'refund_handled' | 'orphan_refund'; id: string; title: string; detail: string }

const fmt = (d?: string) => d ? new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' }) : '—'
const rupees = (n: any) => `₹${Math.round((Number(n) || 0) * 100) / 100}`
const label = (s?: string) => (s || '').replace(/_/g, ' ')
const th = 'text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3 whitespace-nowrap'
const td = 'px-4 py-3 align-top'

function RideLink({ id }: { id: string }) {
  return <Link href={`/rides/${id}`} className="text-blue-600 hover:underline font-mono text-xs">{String(id).slice(-8)}</Link>
}

function Prepaid({ r }: { r: any }) {
  if (!r.prepaidAmount && !r.prepaidUnlinked) return <span className="text-gray-400">—</span>
  return (
    <div className="text-xs space-y-0.5">
      {r.prepaidAmount > 0 && <div>{rupees(r.prepaidAmount)} via {r.prepaidVia || '?'}</div>}
      {r.prepaidRef && <div className="font-mono text-gray-500 break-all">{r.prepaidRef}</div>}
      {r.prepaidUnlinked && <div className="text-red-600 font-semibold">Payment not linked</div>}
    </div>
  )
}

export default function ReviewPage() {
  const [tab, setTab] = useState<Tab>('rides')
  const [data, setData] = useState<any>({ counts: {}, rows: [], orphans: [] })
  const [page, setPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [act, setAct] = useState<Act | null>(null)
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const limit = 50

  const load = useCallback(() => {
    setLoading(true)
    fetch(`/api/review?tab=${tab}&page=${page}&limit=${limit}`).then(r => r.json())
      .then(d => { setData(d || {}); setLoading(false) })
      .catch(() => setLoading(false))
  }, [tab, page])
  useEffect(() => { load() }, [load])

  const run = async () => {
    if (!act) return
    setBusy(true)
    try {
      const res = act.kind === 'resolve'
        ? await fetch(`/api/rides/${act.id}/report-issue`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: 'resolve', note: note.trim() }),
        })
        : await fetch('/api/review', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: act.kind, ...(act.kind === 'orphan_refund' ? { txId: act.id } : { rideId: act.id }), note: note.trim() }),
        })
      const d = await res.json().catch(() => ({}))
      if (res.ok) {
        setToast({ msg: d.already ? 'Already done earlier — nothing changed' : act.kind === 'orphan_refund' ? `Refunded ${rupees(d.amount)} to the rider's wallet` : 'Done', type: 'success' })
        setAct(null); setNote(''); load()
      } else {
        setToast({ msg: d?.error || 'Failed', type: 'error' })
      }
    } catch (e: any) {
      setToast({ msg: e?.message || 'Failed', type: 'error' })
    } finally { setBusy(false) }
  }

  const counts = data.counts || {}
  const rows: any[] = data.rows || []
  const total = Number(data.total) || 0
  const pages = Math.max(1, Math.ceil(Math.max(total, Number(data.orphanTotal) || 0) / limit))
  const btn = 'px-3 py-1.5 rounded-lg text-xs font-semibold whitespace-nowrap'
  const empty = (cols: number, what: string) => <tr><td colSpan={cols} className="px-4 py-8 text-center text-gray-400">{loading ? 'Loading…' : `No ${what}`}</td></tr>

  return (
    <div>
      <Header title="Needs Review" />
      <div className="p-6 space-y-4">
        <div className="flex flex-wrap gap-2" role="tablist">
          {TABS.map(t => (
            <button key={t.key} type="button" role="tab" aria-selected={tab === t.key}
              onClick={() => { setTab(t.key); setPage(1) }}
              className={`px-4 py-2 rounded-lg text-sm font-medium border flex items-center gap-2 ${tab === t.key ? 'bg-primary text-white border-primary' : 'bg-white text-gray-700 hover:bg-gray-50'}`}>
              {t.label}
              <span className={`min-w-[22px] px-1.5 py-0.5 rounded-full text-[11px] font-bold ${(counts[t.key] || 0) > 0 ? (tab === t.key ? 'bg-white/25' : 'bg-red-500 text-white') : 'bg-gray-100 text-gray-500'}`}>{counts[t.key] ?? '…'}</span>
            </button>
          ))}
        </div>

        {tab === 'rides' && (
          <div className="bg-white rounded-xl border overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50"><tr>
                {['Ride', 'Reason', 'Status', 'Flagged', 'Rider / Driver', 'Reports', 'Refund', 'Prepaid', ''].map(h => <th key={h} className={th}>{h}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-50">
                {rows.length === 0 ? empty(9, 'flagged rides') : rows.map(r => (
                  <tr key={r._id} className="hover:bg-gray-50">
                    <td className={td}><RideLink id={r._id} /><div className="text-xs text-gray-500 capitalize">{label(r.service)} · {r.paymentMode}</div></td>
                    <td className={`${td} font-medium capitalize`}>{label(r.reviewReason) || '—'}</td>
                    <td className={td}><Badge status={r.status} /></td>
                    <td className={`${td} text-xs whitespace-nowrap`}>{fmt(r.needsReviewAt)}{r.stuckSince && <div className="text-orange-600">stuck since {fmt(r.stuckSince)}</div>}</td>
                    <td className={`${td} text-xs`}>{r.riderName || '—'} {r.riderPhone && <span className="text-gray-500">({r.riderPhone})</span>}<div className="text-gray-500">{r.driverName || 'no driver'} {r.driverPhone ? `(${r.driverPhone})` : ''}</div></td>
                    <td className={`${td} text-xs`}>{(r.issueReports || []).length === 0 ? <span className="text-gray-400">—</span> : (r.issueReports || []).slice(-3).map((x: any, i: number) => (
                      <div key={i}><span className="capitalize font-medium">{label(x.kind)}</span> <span className="text-gray-500">{fmt(x.at)}</span>{x.note && <div className="text-gray-600 italic">&ldquo;{x.note}&rdquo;</div>}</div>
                    ))}</td>
                    <td className={`${td} text-xs`}>{r.refundReview ? <span className="text-red-600 font-semibold">{label(r.refundReview)}</span> : r.refundPending ? 'pending' : '—'}{r.refundedAmount > 0 && <div>refunded {rupees(r.refundedAmount)}</div>}</td>
                    <td className={td}><Prepaid r={r} /></td>
                    <td className={`${td} space-y-1.5`}>
                      <button type="button" className={`${btn} bg-green-600 text-white hover:bg-green-700`}
                        onClick={() => { setNote(''); setAct({ kind: 'resolve', id: r._id, title: 'Resolve review', detail: `Clears the flag "${label(r.reviewReason)}" on this ride. It does not move any money.` }) }}>Resolve</button>
                      {/* Force-complete / cancel / OTP unlock / confirm delivery, each with its own confirm dialog. */}
                      <RideActions ride={r} only={['force_complete', 'cancel', 'otp_unlock', 'verbal_confirm']} size="sm"
                        onDone={m => { setToast({ msg: m, type: 'success' }); load() }} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {tab === 'cod' && (
          <div className="bg-white rounded-xl border overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50"><tr>
                {['Ride', 'Still owed', 'COD collected', 'Credited to sender', 'Driver', 'Sender', 'Delivered', ''].map(h => <th key={h} className={th}>{h}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-50">
                {rows.length === 0 ? empty(8, 'COD pending') : rows.map(r => (
                  <tr key={r._id} className="hover:bg-gray-50">
                    <td className={td}><RideLink id={r._id} /></td>
                    <td className={`${td} font-semibold text-red-600`}>{rupees(r.codPendingRemittance)}</td>
                    <td className={td}>{rupees(r.codCollected)}</td>
                    <td className={td}>{rupees(r.codSenderCredited)}</td>
                    <td className={`${td} text-xs`}>{r.driverName || '—'}<div className="text-gray-500">{r.driverPhone}</div></td>
                    <td className={`${td} text-xs`}>{r.senderName || r.riderName || '—'}<div className="text-gray-500">{r.senderPhone || r.riderPhone}</div></td>
                    <td className={`${td} text-xs whitespace-nowrap`}>{fmt(r.deliveredAt || r.codSettledAt)}</td>
                    <td className={td}>
                      <button type="button" className={`${btn} bg-primary text-white`}
                        onClick={() => { setNote(''); setAct({ kind: 'cod_settled', id: r._id, title: 'Mark COD settled', detail: `Records that ${rupees(r.codPendingRemittance)} was collected from ${r.driverName || 'the driver'} and paid to the sender outside the app. No wallet is changed.` }) }}>Mark settled</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {tab === 'refunds' && (
          <>
            <div className="bg-white rounded-xl border overflow-x-auto">
              <div className="px-4 py-3 border-b font-semibold text-gray-700 text-sm">Rides whose refund needs a person ({total})</div>
              <table className="w-full text-sm">
                <thead className="bg-gray-50"><tr>
                  {['Ride', 'Problem', 'Status', 'Rider', 'Prepaid', 'Refunded', 'Attempts', ''].map(h => <th key={h} className={th}>{h}</th>)}
                </tr></thead>
                <tbody className="divide-y divide-gray-50">
                  {rows.length === 0 ? empty(8, 'refund problems') : rows.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className={td}><RideLink id={r._id} /><div className="text-xs text-gray-500 capitalize">{label(r.service)} · {r.paymentMode}</div></td>
                      <td className={`${td} text-xs`}>
                        {r.refundReview && <div className="text-red-600 font-semibold capitalize">{label(r.refundReview)}</div>}
                        {r.needsReview && r.reviewReason === 'refund_stuck' && <div className="text-orange-600 font-semibold">Refund keeps failing</div>}
                      </td>
                      <td className={td}><Badge status={r.status} /></td>
                      <td className={`${td} text-xs`}>{r.riderName || '—'}<div className="text-gray-500">{r.riderPhone}</div></td>
                      <td className={td}><Prepaid r={r} /></td>
                      <td className={td}>{rupees(r.refundedAmount)}</td>
                      <td className={td}>{r.refundAttempts || 0}</td>
                      <td className={`${td} space-y-1`}>
                        {r.refundReview && (
                          <button type="button" className={`${btn} bg-primary text-white block`}
                            onClick={() => { setNote(''); setAct({ kind: 'refund_handled', id: r._id, title: 'Mark refund handled', detail: 'Records that you refunded this rider by hand (for example from Finance → Wallet). This button does not move any money.' }) }}>Mark handled</button>
                        )}
                        {r.needsReview && (
                          <button type="button" className={`${btn} bg-green-600 text-white block`}
                            onClick={() => { setNote(''); setAct({ kind: 'resolve', id: r._id, title: 'Resolve review', detail: `Clears the flag "${label(r.reviewReason)}". It does not move any money.` }) }}>Resolve flag</button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="bg-white rounded-xl border overflow-x-auto">
              <div className="px-4 py-3 border-b text-sm">
                <span className="font-semibold text-gray-700">Wallet prepayments with no booking ({data.orphanTotal || 0})</span>
                <p className="text-xs text-gray-500 mt-1">Outstation wallet payments that never got a ride and that the automatic refund (15 min to 3 days) did not handle: older than 3 days, or held because an unlinked ride was booked at the same time. Check the listed rides first.</p>
              </div>
              <table className="w-full text-sm">
                <thead className="bg-gray-50"><tr>
                  {['Paid at', 'Rider', 'Amount', 'State', 'Unlinked rides near it', ''].map(h => <th key={h} className={th}>{h}</th>)}
                </tr></thead>
                <tbody className="divide-y divide-gray-50">
                  {(data.orphans || []).length === 0 ? empty(6, 'orphan payments') : (data.orphans || []).map((t: any) => (
                    <tr key={t._id} className="hover:bg-gray-50">
                      <td className={`${td} text-xs whitespace-nowrap`}>{fmt(t.createdAt)}</td>
                      <td className={`${td} text-xs`}>{t.userName || '—'}<div className="text-gray-500">{t.userPhone}</div></td>
                      <td className={`${td} font-semibold`}>{rupees(t.amount)}</td>
                      <td className={`${td} text-xs`}>{t.ref === 'orphan-review' ? <span className="text-orange-600">held for review</span> : 'older than 3 days'}</td>
                      <td className={`${td} text-xs`}>{(t.nearbyUnlinkedRides || []).length === 0 ? <span className="text-gray-400">none</span> : t.nearbyUnlinkedRides.map((r: any) => (
                        <div key={r._id}><RideLink id={r._id} /> <span className="text-gray-500">{r.status}</span></div>
                      ))}</td>
                      <td className={td}>
                        <button type="button" className={`${btn} bg-red-600 text-white hover:bg-red-700`}
                          onClick={() => { setNote(''); setAct({ kind: 'orphan_refund', id: t._id, title: 'Refund to wallet', detail: `Credits ${rupees(t.amount)} back to ${t.userName || 'the rider'}'s Gora wallet. A payment can be refunded only once.` }) }}>Refund to wallet</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}

        {tab === 'withdrawals' && (
          <div className="bg-white rounded-xl border overflow-x-auto">
            <div className="px-4 py-3 border-b text-xs text-gray-500">Pending withdrawals to a bank account added or changed in the 7 days before the request — a common sign of a taken-over account. Call the driver on their registered number before paying. Approve or reject in <Link href="/finance/withdrawals" className="text-blue-600 hover:underline">Finance → Withdrawals</Link>.</div>
            <table className="w-full text-sm">
              <thead className="bg-gray-50"><tr>
                {['Requested', 'Driver', 'Amount', 'Bank', 'Account', ''].map(h => <th key={h} className={th}>{h}</th>)}
              </tr></thead>
              <tbody className="divide-y divide-gray-50">
                {rows.length === 0 ? empty(6, 'withdrawals to review') : rows.map(w => (
                  <tr key={w._id} className="hover:bg-gray-50">
                    <td className={`${td} text-xs whitespace-nowrap`}>{fmt(w.createdAt)}</td>
                    <td className={`${td} text-xs`}>{w.driverName || '—'}<div className="text-gray-500">{w.driverPhone}</div></td>
                    <td className={`${td} font-semibold`}>{rupees(w.amount)}</td>
                    <td className={`${td} text-xs`}>{w.bankName || '—'}<div className="text-gray-500">{w.accountHolderName}</div></td>
                    <td className={`${td} font-mono text-xs`}>{w.accountNumber}</td>
                    <td className={td}><Link href="/finance/withdrawals" className={`${btn} bg-primary text-white inline-block`}>Open withdrawals</Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="flex items-center justify-end gap-2 text-sm text-gray-600">
          <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
          <span>Page {page} of {pages}</span>
          <button type="button" className="px-3 py-1.5 border rounded-lg disabled:opacity-40" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</button>
        </div>
      </div>

      {act && (
        <Modal title={act.title} onClose={() => !busy && setAct(null)} size="sm">
          <div className="space-y-4">
            <p className="text-sm text-gray-600">{act.detail}</p>
            <textarea value={note} onChange={e => setNote(e.target.value)} rows={3} maxLength={500}
              placeholder="Note (what you did, reference no.)" aria-label="Note"
              className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm" />
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setAct(null)} disabled={busy} className="px-4 py-2 border rounded-lg text-sm">Cancel</button>
              <button type="button" onClick={run} disabled={busy} className="px-4 py-2 bg-primary text-white rounded-lg text-sm font-semibold disabled:opacity-50">{busy ? 'Working…' : 'Confirm'}</button>
            </div>
          </div>
        </Modal>
      )}
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
