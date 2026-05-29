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

  const fetchWithdrawals = () => {
    const params = new URLSearchParams({ limit: '100' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    fetch(`/api/finance/withdrawals?${params}`)
      .then(r => r.json())
      .then(d => { setRequests(d.withdrawals || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchWithdrawals() }, [statusFilter])

  const approve = async (id: string) => {
    const res = await fetch(`/api/finance/withdrawals/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'approve' }),
    })
    if (res.ok) {
      setRequests(prev => prev.map(r => r._id === id ? { ...r, status: 'approved' } : r))
      setToast({ msg: 'Withdrawal approved and processed', type: 'success' })
    }
  }

  const reject = async (id: string) => {
    const res = await fetch(`/api/finance/withdrawals/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'reject' }),
    })
    if (res.ok) {
      setRequests(prev => prev.map(r => r._id === id ? { ...r, status: 'rejected' } : r))
      setToast({ msg: 'Withdrawal rejected', type: 'error' })
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
            <select aria-label="Filter by status" value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
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
                    {['Driver', 'Amount', 'Bank Details', 'Requested Date', 'Status', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {requests.map(r => (
                    <tr key={r._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-medium text-gray-800">{r.driverName || '—'}</td>
                      <td className="px-4 py-3 font-bold text-gray-900">₹{(r.amount || 0).toLocaleString()}</td>
                      <td className="px-4 py-3 text-gray-600 text-xs font-mono">
                        {r.bankName ? `${r.bankName} ${r.accountNumber ? `**** ${r.accountNumber.slice(-4)}` : ''}` : '—'}
                      </td>
                      <td className="px-4 py-3 text-gray-500">{r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'}</td>
                      <td className="px-4 py-3"><Badge status={r.status} /></td>
                      <td className="px-4 py-3">
                        {r.status === 'pending' && (
                          <div className="flex gap-2">
                            <button type="button" onClick={() => approve(r._id)}
                              className="flex items-center gap-1 px-3 py-1 bg-green-50 text-green-700 rounded-lg text-xs font-medium hover:bg-green-100 border border-green-200">
                              <CheckCircle className="w-3.5 h-3.5" /> Approve
                            </button>
                            <button type="button" onClick={() => reject(r._id)}
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
                    <tr><td colSpan={6} className="text-center text-gray-400 py-12">No withdrawal requests</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
