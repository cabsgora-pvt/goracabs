'use client'
import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { Pager } from '@/components/ui/pager'
import { refreshAlerts } from '@/components/admin-alerts'
import { downloadText } from '@/lib/csv'
import { DollarSign, CheckCircle, XCircle, Clock, Download } from 'lucide-react'

const LIMIT = 50
const inr = (n: number) => `₹${Math.round(n || 0).toLocaleString('en-IN')}`
const fmt = (d?: string) => d ? new Date(d).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' }) : '—'
function age(d?: string) {
  if (!d) return ''
  const h = (Date.now() - new Date(d).getTime()) / 3600000
  if (h < 1) return `${Math.max(1, Math.round(h * 60))} min`
  if (h < 48) return `${Math.floor(h)} h`
  return `${Math.floor(h / 24)} days`
}

export default function WithdrawalsPage() {
  const [requests, setRequests] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  // The queue first: pending, oldest first (server order).
  const [statusFilter, setStatusFilter] = useState('pending')
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [totals, setTotals] = useState<Record<string, { count: number; amount: number }>>({})
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const [approveTarget, setApproveTarget] = useState<any | null>(null)
  const [bank, setBank] = useState<any | null>(null)
  const [rejectTarget, setRejectTarget] = useState<any | null>(null)
  const [reason, setReason] = useState('')
  const [payoutRef, setPayoutRef] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [exporting, setExporting] = useState(false)

  const fetchWithdrawals = useCallback(() => {
    setLoading(true)
    const params = new URLSearchParams({ page: String(page), limit: String(LIMIT) })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    fetch(`/api/finance/withdrawals?${params}`)
      .then(r => r.json())
      .then(d => { setRequests(d.withdrawals || []); setTotal(d.total || 0); setTotals(d.totals || {}); setLoading(false) })
      .catch(() => setLoading(false))
  }, [page, statusFilter])

  useEffect(() => { fetchWithdrawals() }, [fetchWithdrawals])

  // Full bank details are behind the password (the list has the last 4 only).
  const openApprove = async (r: any) => {
    setPayoutRef(''); setBank(null)
    try {
      const res = await fetch('/api/finance/withdrawals/bank', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: r._id }),
      })
      const d = await res.json().catch(() => ({}))
      if (!res.ok) { setToast({ msg: d.error || 'Could not load the bank details', type: 'error' }); return }
      setBank(d.bank)
      setApproveTarget(r)
    } catch (e: any) {
      setToast({ msg: e?.message || 'Could not load the bank details', type: 'error' })
    }
  }

  const confirmApprove = async () => {
    if (!approveTarget) return
    const id = approveTarget._id
    setSubmitting(true)
    try {
      const res = await fetch(`/api/finance/withdrawals/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'approve', payoutRef: payoutRef.trim() }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setToast({ msg: 'Withdrawal approved and processed', type: 'success' })
        setApproveTarget(null); setBank(null)
        fetchWithdrawals(); refreshAlerts()
      } else {
        setToast({ msg: data?.error || 'Failed to approve withdrawal', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to approve withdrawal', type: 'error' })
    } finally {
      setSubmitting(false)
    }
  }

  const confirmReject = async () => {
    if (!rejectTarget || !reason.trim()) return
    const id = rejectTarget._id
    setSubmitting(true)
    try {
      const res = await fetch(`/api/finance/withdrawals/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'reject', note: reason.trim() }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setToast({ msg: 'Withdrawal rejected', type: 'success' })
        setRejectTarget(null)
        setReason('')
        fetchWithdrawals(); refreshAlerts()
      } else {
        setToast({ msg: data?.error || 'Failed to reject withdrawal', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to reject withdrawal', type: 'error' })
    } finally {
      setSubmitting(false)
    }
  }

  // Bank batch CSV with full account numbers: password + audit on the server.
  const exportCsv = async () => {
    setExporting(true)
    try {
      const res = await fetch('/api/finance/withdrawals/export', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: statusFilter }),
      })
      if (!res.ok) {
        const d = await res.json().catch(() => ({}))
        setToast({ msg: d.error || 'Export failed', type: 'error' }); return
      }
      const text = await res.text()
      downloadText(`gora-withdrawals-${statusFilter}-${new Date().toISOString().slice(0, 10)}.csv`, text)
      setToast({ msg: `Exported ${res.headers.get('X-Row-Count') || ''} rows`, type: 'success' })
    } catch (e: any) {
      setToast({ msg: e?.message || 'Export failed', type: 'error' })
    } finally {
      setExporting(false)
    }
  }

  const tp = totals.pending || { count: 0, amount: 0 }
  const ta = totals.approved || { count: 0, amount: 0 }
  const tr = totals.rejected || { count: 0, amount: 0 }

  return (
    <div>
      <Header title="Withdrawals" />
      <div className="p-6 space-y-6">
        <PageHeader title="Withdrawal Requests" subtitle="Review and process driver withdrawal requests — pending ones oldest first" />

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <StatsCard icon={Clock} label="Pending" value={`${tp.count} · ${inr(tp.amount)}`} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={CheckCircle} label="Paid out (approved)" value={`${ta.count} · ${inr(ta.amount)}`} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={DollarSign} label="Rejected" value={`${tr.count} · ${inr(tr.amount)}`} iconColor="text-red-600" iconBg="bg-red-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3 items-center">
            <select aria-label="Filter by status" title="Filter by status" value={statusFilter} onChange={e => { setPage(1); setStatusFilter(e.target.value) }}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
              <option value="all">All Status</option>
            </select>
            <div className="flex-1" />
            <button type="button" onClick={exportCsv} disabled={exporting}
              title="CSV with full account numbers for the bank's bulk payout. Asks for your password; every export is logged."
              className="px-4 py-2 border border-gray-300 rounded-lg text-sm font-medium hover:bg-gray-50 disabled:opacity-50 flex items-center gap-2">
              <Download className="w-4 h-4" /> {exporting ? 'Exporting…' : 'Export bank CSV'}
            </button>
          </div>

          {loading && requests.length === 0 ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className={`overflow-x-auto ${loading ? 'opacity-60' : ''}`}>
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Requested (IST)', 'Age', 'Driver', 'Number', 'Zone', 'Account', 'Amount', 'Status', 'UTR / processed', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {requests.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 text-gray-600 whitespace-nowrap">{fmt(r.createdAt)}</td>
                      <td className={`px-4 py-3 whitespace-nowrap text-xs ${r.status === 'pending' && Date.now() - new Date(r.createdAt).getTime() > 48 * 3600000 ? 'text-red-600 font-semibold' : 'text-gray-500'}`}>
                        {r.status === 'pending' ? age(r.createdAt) : '—'}
                      </td>
                      <td className="px-4 py-3 font-medium text-gray-800">
                        {r.driverId ? <Link href={`/drivers/${r.driverId}`} className="hover:text-primary">{r.driverName || '—'}</Link> : (r.driverName || '—')}
                        {r.vehicleType && <p className="text-xs text-gray-400 font-normal">{r.vehicleType}</p>}
                      </td>
                      <td className="px-4 py-3 text-gray-600">{r.driverPhone || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.zoneName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs whitespace-nowrap">
                        {r.bankName || 'Bank'} ••••{r.accountLast4 || '????'}
                        {r.bankChangedRecently && <span className="block text-amber-700">bank changed &lt; 7 days</span>}
                      </td>
                      <td className="px-4 py-3 font-bold text-gray-900">{inr(r.amount)}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                      <td className="px-4 py-3 text-xs text-gray-600">
                        {r.payoutRef && <p className="font-mono text-gray-800">{r.payoutRef}</p>}
                        {r.status === 'rejected' && r.note && <p className="text-red-600">{r.note}</p>}
                        {r.processedAt && <p className="text-gray-400 whitespace-nowrap">{fmt(r.processedAt)}{r.processedBy ? ` · ${r.processedBy}` : ''}</p>}
                        {!r.payoutRef && !r.processedAt && '—'}
                      </td>
                      <td className="px-4 py-3">
                        {r.status === 'pending' && (
                          <div className="flex gap-2">
                            <button type="button" onClick={() => openApprove(r)}
                              className="flex items-center gap-1 px-3 py-1 bg-green-50 text-green-700 rounded-lg text-xs font-medium hover:bg-green-100 border border-green-200">
                              <CheckCircle className="w-3.5 h-3.5" /> Approve
                            </button>
                            <button type="button" onClick={() => { setRejectTarget(r); setReason('') }}
                              className="flex items-center gap-1 px-3 py-1 bg-red-50 text-red-600 rounded-lg text-xs font-medium hover:bg-red-100 border border-red-200">
                              <XCircle className="w-3.5 h-3.5" /> Reject
                            </button>
                          </div>
                        )}
                        {r.status !== 'pending' && <span className="text-gray-400 text-xs">—</span>}
                      </td>
                    </tr>
                  ))}
                  {requests.length === 0 && (
                    <tr><td colSpan={10} className="text-center text-gray-400 py-12">No withdrawal requests</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
          <div className="px-4 border-t border-gray-100">
            <Pager page={page} limit={LIMIT} total={total} onPage={setPage} noun={['request', 'requests']} />
          </div>
        </div>
      </div>

      {approveTarget && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md">
            <div className="p-5 border-b border-gray-100">
              <h3 className="text-lg font-semibold text-gray-900">Confirm Withdrawal Approval</h3>
              <p className="text-sm text-gray-500 mt-1">Review the bank details before approving.</p>
            </div>
            <div className="p-5 space-y-3 text-sm">
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Driver</span>
                <span className="font-medium text-gray-900 text-right">{approveTarget.driverName || '—'} · requested {fmt(approveTarget.createdAt)}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Account Holder</span>
                <span className="font-medium text-gray-900 text-right">{bank?.accountHolderName || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Bank</span>
                <span className="font-medium text-gray-900 text-right">{bank?.bankName || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Account Number</span>
                <span className="font-mono font-medium text-gray-900 text-right break-all">{bank?.accountNumber || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">IFSC</span>
                <span className="font-mono font-medium text-gray-900 text-right">{bank?.ifscCode || '—'}</span>
              </div>
              <div className="flex justify-between gap-4 pt-2 border-t border-gray-100">
                <span className="text-gray-500">Amount</span>
                <span className="font-bold text-gray-900 text-right">{inr(approveTarget.amount)}</span>
              </div>
              {approveTarget.bankChangedRecently && (
                <div className="rounded-lg bg-amber-50 border border-amber-200 text-amber-800 px-3 py-2 text-xs">
                  This bank account was added or changed in the last 7 days. Confirm it with the driver before paying.
                </div>
              )}
              <div className="pt-2">
                <label htmlFor="payout-ref" className="block text-gray-500 mb-1">Payout reference / UTR (required)</label>
                <input id="payout-ref" title="Payout reference" value={payoutRef} onChange={e => setPayoutRef(e.target.value)}
                  placeholder="Bank UTR after you transfer the money"
                  className="w-full px-3 py-2 rounded-lg border border-gray-200 text-sm focus:outline-none focus:ring-2 focus:ring-green-500" />
              </div>
            </div>
            <div className="p-5 border-t border-gray-100 flex justify-end gap-2">
              <button type="button" onClick={() => { setApproveTarget(null); setBank(null) }} disabled={submitting}
                className="px-4 py-2 rounded-lg text-sm font-medium text-gray-600 border border-gray-200 hover:bg-gray-50 disabled:opacity-50">
                Cancel
              </button>
              <button type="button" onClick={confirmApprove} disabled={submitting || !payoutRef.trim()}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-green-600 text-white hover:bg-green-700 disabled:opacity-50">
                Confirm &amp; Approve
              </button>
            </div>
          </div>
        </div>
      )}

      {rejectTarget && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-xl shadow-xl w-full max-w-md">
            <div className="p-5 border-b border-gray-100">
              <h3 className="text-lg font-semibold text-gray-900">Reject Withdrawal</h3>
              <p className="text-sm text-gray-500 mt-1">Provide a reason for rejecting this request. The held amount goes back to the driver&apos;s wallet.</p>
            </div>
            <div className="p-5">
              <label htmlFor="reject-reason" className="block text-sm font-medium text-gray-700 mb-1">Reason</label>
              <textarea id="reject-reason" aria-label="Rejection reason" title="Rejection reason" value={reason} onChange={e => setReason(e.target.value)}
                rows={3} placeholder="Enter the reason for rejection"
                className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-red-500" />
            </div>
            <div className="p-5 border-t border-gray-100 flex justify-end gap-2">
              <button type="button" onClick={() => { setRejectTarget(null); setReason('') }} disabled={submitting}
                className="px-4 py-2 rounded-lg text-sm font-medium text-gray-600 border border-gray-200 hover:bg-gray-50 disabled:opacity-50">
                Cancel
              </button>
              <button type="button" onClick={confirmReject} disabled={submitting || !reason.trim()}
                className="px-4 py-2 rounded-lg text-sm font-medium bg-red-600 text-white hover:bg-red-700 disabled:opacity-50">
                Reject
              </button>
            </div>
          </div>
        </div>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
