'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { DollarSign, CheckCircle, XCircle, Clock } from 'lucide-react'

export default function WithdrawalsPage() {
  const [requests, setRequests] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState('all')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const [approveTarget, setApproveTarget] = useState<any | null>(null)
  const [rejectTarget, setRejectTarget] = useState<any | null>(null)
  const [reason, setReason] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const fetchWithdrawals = () => {
    const params = new URLSearchParams({ limit: '100' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    fetch(`/api/finance/withdrawals?${params}`)
      .then(r => r.json())
      .then(d => { setRequests(d.withdrawals || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchWithdrawals() }, [statusFilter])

  const confirmApprove = async () => {
    if (!approveTarget) return
    const id = approveTarget._id
    setSubmitting(true)
    try {
      const res = await fetch(`/api/finance/withdrawals/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'approve' }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok) {
        setRequests(prev => prev.map(r => r._id === id ? { ...r, status: 'approved' } : r))
        setToast({ msg: 'Withdrawal approved and processed', type: 'success' })
        setApproveTarget(null)
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
        setRequests(prev => prev.map(r => r._id === id ? { ...r, status: 'rejected', note: reason.trim() } : r))
        setToast({ msg: 'Withdrawal rejected', type: 'success' })
        setRejectTarget(null)
        setReason('')
      } else {
        setToast({ msg: data?.error || 'Failed to reject withdrawal', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to reject withdrawal', type: 'error' })
    } finally {
      setSubmitting(false)
    }
  }

  const pending = requests.filter(r => r.status === 'pending').length
  const totalPaid = requests.filter(r => r.status === 'approved').reduce((s, r) => s + (r.amount || 0), 0)

  return (
    <div>
      <Header title="Withdrawals" />
      <div className="p-6 space-y-6">
        <PageHeader title="Withdrawal Requests" subtitle="Review and process driver withdrawal requests" />

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <StatsCard icon={Clock} label="Pending" value={pending} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={CheckCircle} label="Approved" value={requests.filter(r => r.status === 'approved').length} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={DollarSign} label="Total Paid Out" value={`₹${totalPaid.toLocaleString()}`} iconColor="text-blue-600" iconBg="bg-blue-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100">
            <select aria-label="Filter by status" title="Filter by status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="approved">Approved</option>
              <option value="rejected">Rejected</option>
            </select>
          </div>

          {loading ? (
            <div className="flex items-center justify-center py-12">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Driver', 'Number', 'Vehicle', 'Zone', 'Amount', 'Status', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {requests.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-medium text-gray-800">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.driverPhone || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.vehicleType || '—'}</td>
                      <td className="px-4 py-3 text-gray-600">{r.zoneName || '—'}</td>
                      <td className="px-4 py-3 font-bold text-gray-900">₹{(r.amount || 0).toLocaleString()}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                      <td className="px-4 py-3">
                        {r.status === 'pending' && (
                          <div className="flex gap-2">
                            <button type="button" onClick={() => setApproveTarget(r)}
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
                    <tr><td colSpan={7} className="text-center text-gray-400 py-12">No withdrawal requests</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
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
                <span className="text-gray-500">Account Holder</span>
                <span className="font-medium text-gray-900 text-right">{approveTarget.accountHolderName || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Bank</span>
                <span className="font-medium text-gray-900 text-right">{approveTarget.bankName || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">Account Number</span>
                <span className="font-mono font-medium text-gray-900 text-right break-all">{approveTarget.accountNumber || '—'}</span>
              </div>
              <div className="flex justify-between gap-4">
                <span className="text-gray-500">IFSC</span>
                <span className="font-mono font-medium text-gray-900 text-right">{approveTarget.ifscCode || '—'}</span>
              </div>
              <div className="flex justify-between gap-4 pt-2 border-t border-gray-100">
                <span className="text-gray-500">Amount</span>
                <span className="font-bold text-gray-900 text-right">₹{(approveTarget.amount || 0).toLocaleString()}</span>
              </div>
            </div>
            <div className="p-5 border-t border-gray-100 flex justify-end gap-2">
              <button type="button" onClick={() => setApproveTarget(null)} disabled={submitting}
                className="px-4 py-2 rounded-lg text-sm font-medium text-gray-600 border border-gray-200 hover:bg-gray-50 disabled:opacity-50">
                Cancel
              </button>
              <button type="button" onClick={confirmApprove} disabled={submitting}
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
              <p className="text-sm text-gray-500 mt-1">Provide a reason for rejecting this request.</p>
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
