'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Clock, CheckCircle, XCircle, ChevronDown, ChevronRight, FileText } from 'lucide-react'

export default function PendingDriversPage() {
  const [pendingDrivers, setPendingDrivers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [confirmId, setConfirmId] = useState<string | null>(null)
  const [rejectId, setRejectId] = useState<string | null>(null)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  useEffect(() => {
    fetch('/api/drivers/pending')
      .then(r => r.json())
      .then(d => { setPendingDrivers(d.drivers || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const approve = async (id: string) => {
    const res = await fetch(`/api/drivers/${id}/approve`, { method: 'POST' })
    if (res.ok) {
      setPendingDrivers(prev => prev.filter(d => d._id !== id))
      setConfirmId(null)
      setToast({ msg: 'Driver approved successfully!', type: 'success' })
    }
  }

  const reject = async (id: string) => {
    const res = await fetch(`/api/drivers/${id}/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: 'Application rejected by admin' }),
    })
    if (res.ok) {
      setPendingDrivers(prev => prev.filter(d => d._id !== id))
      setRejectId(null)
      setToast({ msg: 'Driver application rejected', type: 'error' })
    }
  }

  const driverToConfirm = pendingDrivers.find(d => d._id === confirmId)
  const driverToReject = pendingDrivers.find(d => d._id === rejectId)

  if (loading) return (
    <div><Header title="Pending Drivers" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Pending Drivers" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Pending Driver Approvals"
          subtitle={`${pendingDrivers.length} applications awaiting review`}
        />

        {pendingDrivers.length === 0 ? (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-12 text-center">
            <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-3" />
            <p className="text-gray-700 font-semibold">All caught up!</p>
            <p className="text-gray-400 text-sm mt-1">No pending driver approvals</p>
          </div>
        ) : (
          <div className="space-y-3">
            {pendingDrivers.map(d => (
              <div key={d._id} className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
                <div className="flex flex-wrap items-center gap-4 p-4">
                  <div className="flex items-center gap-3 flex-1 min-w-0">
                    <div className="w-10 h-10 rounded-full bg-yellow-100 flex items-center justify-center text-yellow-700 font-bold flex-shrink-0">
                      {d.name?.charAt(0) || '?'}
                    </div>
                    <div className="min-w-0">
                      <p className="font-semibold text-gray-900">{d.name}</p>
                      <p className="text-xs text-gray-500">{d.phone}</p>
                    </div>
                  </div>
                  <div className="text-sm text-gray-600">{d.vehicleNumber}</div>
                  <div className="text-sm text-gray-600">{d.vehicleType}</div>
                  <div className="text-xs text-gray-400">{d.createdAt ? new Date(d.createdAt).toLocaleDateString() : '—'}</div>
                  <div className="flex items-center gap-2">
                    <button type="button" onClick={() => setConfirmId(d._id)}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-green-50 text-green-700 rounded-lg text-sm font-medium hover:bg-green-100 border border-green-200">
                      <CheckCircle className="w-4 h-4" /> Approve
                    </button>
                    <button type="button" onClick={() => setRejectId(d._id)}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-red-50 text-red-600 rounded-lg text-sm font-medium hover:bg-red-100 border border-red-200">
                      <XCircle className="w-4 h-4" /> Reject
                    </button>
                    <button type="button" onClick={() => setExpanded(expanded === d._id ? null : d._id)}
                      className="p-1.5 hover:bg-gray-100 rounded-lg text-gray-500">
                      {expanded === d._id ? <ChevronDown className="w-5 h-5" /> : <ChevronRight className="w-5 h-5" />}
                    </button>
                  </div>
                </div>

                {expanded === d._id && (
                  <div className="border-t border-gray-100 p-4 bg-gray-50">
                    <p className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                      <FileText className="w-4 h-4" /> Documents
                    </p>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                      {(d.documents || []).map((doc: any, i: number) => (
                        <div key={doc._id || i} className="bg-white rounded-lg border border-gray-200 p-3">
                          <p className="text-sm text-gray-700 font-medium mb-1">{doc.name}</p>
                          <Badge status={doc.status} />
                        </div>
                      ))}
                      {(!d.documents || d.documents.length === 0) && (
                        <p className="text-sm text-gray-400 col-span-4">No documents uploaded</p>
                      )}
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {confirmId && driverToConfirm && (
        <Modal title="Confirm Approval" onClose={() => setConfirmId(null)} size="sm">
          <div className="text-center">
            <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-3" />
            <p className="text-gray-700">Approve driver <strong>{driverToConfirm.name}</strong>?</p>
            <p className="text-gray-500 text-sm mt-1">This will allow them to start accepting rides.</p>
            <div className="flex gap-3 mt-5">
              <button type="button" onClick={() => setConfirmId(null)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="button" onClick={() => approve(confirmId)}
                className="flex-1 bg-green-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-green-700">Approve</button>
            </div>
          </div>
        </Modal>
      )}

      {rejectId && driverToReject && (
        <Modal title="Reject Application" onClose={() => setRejectId(null)} size="sm">
          <div className="text-center">
            <XCircle className="w-12 h-12 text-red-500 mx-auto mb-3" />
            <p className="text-gray-700">Reject application for <strong>{driverToReject.name}</strong>?</p>
            <p className="text-gray-500 text-sm mt-1">The driver will be notified of the rejection.</p>
            <div className="flex gap-3 mt-5">
              <button type="button" onClick={() => setRejectId(null)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="button" onClick={() => reject(rejectId)}
                className="flex-1 bg-red-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-red-700">Reject</button>
            </div>
          </div>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
