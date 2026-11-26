'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Pager } from '@/components/ui/pager'
import { refreshAlerts } from '@/components/admin-alerts'
import Link from 'next/link'
import {
  Clock, CheckCircle, XCircle, ChevronDown, ChevronRight,
  FileText, MapPin, Car, CreditCard, User, ExternalLink,
} from 'lucide-react'

const LIMIT = 50
const waited = (d?: string) => {
  if (!d) return ''
  const h = Math.floor((Date.now() - new Date(d).getTime()) / 3600000)
  return h < 24 ? `${h}h waiting` : `${Math.floor(h / 24)}d waiting`
}

export default function PendingDriversPage() {
  const [pendingDrivers, setPendingDrivers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [confirmId, setConfirmId] = useState<string | null>(null)
  const [rejectId, setRejectId] = useState<string | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)
  const [zoneId, setZoneId] = useState('')
  const [vehicle, setVehicle] = useState('')
  const [zones, setZones] = useState<any[]>([])
  const [vehicleTypes, setVehicleTypes] = useState<string[]>([])
  // Why the last approve / reject failed, with the documents still missing.
  const [actionError, setActionError] = useState<{ id: string; error: string; missing?: { key: string; name: string }[] } | null>(null)

  const load = () => {
    setLoading(true)
    const p = new URLSearchParams({ page: String(page), limit: String(LIMIT) })
    if (zoneId) p.set('zoneId', zoneId)
    if (vehicle) p.set('vehicle', vehicle)
    fetch(`/api/drivers/pending?${p}`)
      .then(r => r.json())
      .then(d => { setPendingDrivers(d.drivers || []); setTotal(d.total || 0); setLoading(false) })
      .catch(() => setLoading(false))
  }
  useEffect(() => { load() }, [page, zoneId, vehicle]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    fetch('/api/zones').then(r => r.json()).then(d => setZones(d.zones || [])).catch(() => {})
    fetch('/api/vehicles/types').then(r => r.json())
      .then(d => setVehicleTypes(Array.from(new Set((d.types || []).map((t: any) => String(t.name || '')).filter(Boolean))) as string[]))
      .catch(() => {})
  }, [])

  const approve = async (id: string) => {
    const res = await fetch(`/api/drivers/${id}/approve`, { method: 'POST' })
    const d = await res.json().catch(() => ({}))
    if (res.ok) {
      setPendingDrivers(prev => prev.filter(x => x._id !== id))
      setTotal(t => Math.max(0, t - 1))
      setConfirmId(null)
      setActionError(null)
      setToast({ msg: 'Driver approved successfully!', type: 'success' })
      refreshAlerts()
    } else {
      setConfirmId(null)
      setActionError({ id, error: d.error || `Approval failed (${res.status})`, missing: d.missing })
      setToast({ msg: d.error || 'Approval failed', type: 'error' })
    }
  }

  const reject = async (id: string) => {
    const res = await fetch(`/api/drivers/${id}/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: rejectReason || 'Application rejected by admin' }),
    })
    const d = await res.json().catch(() => ({}))
    if (res.ok) {
      setPendingDrivers(prev => prev.filter(x => x._id !== id))
      setTotal(t => Math.max(0, t - 1))
      setRejectId(null)
      setRejectReason('')
      setActionError(null)
      setToast({ msg: 'Driver application rejected', type: 'success' })
      refreshAlerts()
    } else {
      setRejectId(null)
      setActionError({ id, error: d.error || `Reject failed (${res.status})` })
      setToast({ msg: d.error || 'Reject failed', type: 'error' })
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
          subtitle={`${total} application${total === 1 ? '' : 's'} awaiting review — oldest first`}
        />

        <div className="bg-white rounded-xl border p-4 flex flex-wrap gap-3 items-end">
          <div>
            <label className="block text-xs text-gray-500 mb-1">Zone</label>
            <select aria-label="Zone" value={zoneId} onChange={e => { setZoneId(e.target.value); setPage(1) }} className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white">
              <option value="">All zones</option>
              <option value="none">No zone</option>
              {zones.map(z => <option key={z._id} value={z._id}>{z.name}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-xs text-gray-500 mb-1">Vehicle</label>
            <select aria-label="Vehicle type" value={vehicle} onChange={e => { setVehicle(e.target.value); setPage(1) }} className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white">
              <option value="">All vehicles</option>
              {vehicleTypes.map(v => <option key={v} value={v}>{v}</option>)}
            </select>
          </div>
        </div>

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
                {/* Row header */}
                <div className="flex flex-wrap items-center gap-4 p-4">
                  <div className="flex items-center gap-3 flex-1 min-w-0">
                    <div className="w-10 h-10 rounded-full bg-yellow-100 flex items-center justify-center text-yellow-700 font-bold flex-shrink-0">
                      {d.name?.charAt(0) || '?'}
                    </div>
                    <div className="min-w-0">
                      <Link href={`/drivers/${d._id}`} className="font-semibold text-gray-900 hover:text-primary flex items-center gap-1">
                        {d.name || 'Unnamed'} <ExternalLink className="w-3 h-3 text-gray-400" />
                      </Link>
                      <p className="text-xs text-gray-500">{d.phone}</p>
                    </div>
                  </div>
                  <div className="hidden md:flex items-center gap-1 text-sm text-gray-500">
                    <MapPin className="w-3.5 h-3.5" />
                    <span>{d.zoneName || d.state || '—'}</span>
                  </div>
                  <div className="hidden md:flex items-center gap-1 text-sm text-gray-500">
                    <Car className="w-3.5 h-3.5" />
                    <span>{d.selectedVehicleTypeName || d.vehicleType || '—'}</span>
                  </div>
                  <div className="text-xs font-mono text-gray-600">{d.vehicleRegistrationNumber || d.vehicleNumber || '—'}</div>
                  <div className="text-xs text-gray-400" title={d.createdAt ? new Date(d.createdAt).toLocaleString() : ''}>
                    {d.createdAt ? new Date(d.createdAt).toLocaleDateString() : '—'}
                    <span className="block text-amber-600">{waited(d.createdAt)}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <button type="button" onClick={() => setConfirmId(d._id)}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-green-50 text-green-700 rounded-lg text-sm font-medium hover:bg-green-100 border border-green-200">
                      <CheckCircle className="w-4 h-4" /> Approve
                    </button>
                    <button type="button" onClick={() => { setRejectId(d._id); setRejectReason('') }}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-red-50 text-red-600 rounded-lg text-sm font-medium hover:bg-red-100 border border-red-200">
                      <XCircle className="w-4 h-4" /> Reject
                    </button>
                    <button type="button" onClick={() => setExpanded(expanded === d._id ? null : d._id)}
                      className="p-1.5 hover:bg-gray-100 rounded-lg text-gray-500">
                      {expanded === d._id ? <ChevronDown className="w-5 h-5" /> : <ChevronRight className="w-5 h-5" />}
                    </button>
                  </div>
                </div>

                {actionError && actionError.id === d._id && (
                  <div className="mx-4 mb-3 p-3 rounded-lg bg-red-50 border border-red-200 text-sm text-red-700" role="alert">
                    <p className="font-semibold">{actionError.error}</p>
                    {!!actionError.missing?.length && (
                      <ul className="list-disc ml-5 mt-1">
                        {(actionError.missing || []).map(m => <li key={m.key}>{m.name}</li>)}
                      </ul>
                    )}
                    <Link href={`/drivers/${d._id}`} className="inline-block mt-1 text-red-800 underline">Open the driver to review documents</Link>
                  </div>
                )}

                {/* Expanded details */}
                {expanded === d._id && (
                  <div className="border-t border-gray-100 bg-gray-50 p-4 space-y-5">
                    {/* Personal + Location */}
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="bg-white rounded-lg border border-gray-100 p-4">
                        <p className="text-xs font-semibold text-gray-500 uppercase mb-3 flex items-center gap-1.5">
                          <User className="w-3.5 h-3.5" /> Personal Info
                        </p>
                        <div className="space-y-2 text-sm">
                          <div className="flex justify-between"><span className="text-gray-500">Name</span><span className="font-medium">{d.name || '—'}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">Phone</span><span className="font-medium">{d.phone}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">Email</span><span className="font-medium">{d.email || '—'}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">State</span><span className="font-medium">{d.state || '—'}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">Zone</span><span className="font-medium">{d.zoneName || '—'}</span></div>
                        </div>
                      </div>

                      <div className="bg-white rounded-lg border border-gray-100 p-4">
                        <p className="text-xs font-semibold text-gray-500 uppercase mb-3 flex items-center gap-1.5">
                          <Car className="w-3.5 h-3.5" /> Vehicle Info
                        </p>
                        <div className="space-y-2 text-sm">
                          <div className="flex justify-between"><span className="text-gray-500">Type</span><span className="font-medium">{d.selectedVehicleTypeName || d.vehicleType || '—'}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">Model</span><span className="font-medium">{d.vehicleModel || '—'}</span></div>
                          <div className="flex justify-between"><span className="text-gray-500">Reg. No.</span><span className="font-mono font-medium text-xs">{d.vehicleRegistrationNumber || d.vehicleNumber || '—'}</span></div>
                        </div>
                      </div>

                      <div className="bg-white rounded-lg border border-gray-100 p-4">
                        <p className="text-xs font-semibold text-gray-500 uppercase mb-3 flex items-center gap-1.5">
                          <CreditCard className="w-3.5 h-3.5" /> Bank Details
                        </p>
                        {d.bankDetails?.accountLast4 ? (
                          <div className="space-y-2 text-sm">
                            <div className="flex justify-between"><span className="text-gray-500">Holder</span><span className="font-medium">{d.bankDetails.accountHolderName || '—'}</span></div>
                            <div className="flex justify-between"><span className="text-gray-500">Bank</span><span className="font-medium">{d.bankDetails.bankName || '—'}</span></div>
                            <div className="flex justify-between"><span className="text-gray-500">Branch</span><span className="font-medium">{d.bankDetails.branch || '—'}</span></div>
                            <div className="flex justify-between"><span className="text-gray-500">Account</span><span className="font-mono font-medium text-xs">{'••••' + d.bankDetails.accountLast4}</span></div>
                            <div className="flex justify-between"><span className="text-gray-500">IFSC</span><span className="font-mono font-medium text-xs">{d.bankDetails.ifscCode || '—'}</span></div>
                            <div className="flex justify-between"><span className="text-gray-500">Type</span><span className="font-medium capitalize">{d.bankDetails.accountType || 'savings'}</span></div>
                          </div>
                        ) : (
                          <p className="text-sm text-gray-400">Not submitted yet</p>
                        )}
                      </div>
                    </div>

                    {/* Documents */}
                    <div>
                      <p className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
                        <FileText className="w-4 h-4" /> Documents
                      </p>
                      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-3">
                        {(d.documents || []).map((doc: any, i: number) => (
                          <div key={doc._id || i} className="bg-white rounded-lg border border-gray-200 p-3 flex flex-col gap-2">
                            <p className="text-xs text-gray-700 font-medium leading-tight">{doc.name}</p>
                            {doc.fileUrl ? (
                              <a href={doc.fileUrl} target="_blank" rel="noopener noreferrer">
                                <img
                                  src={doc.fileUrl}
                                  alt={doc.name}
                                  className="w-full h-20 object-cover rounded border border-gray-100"
                                  onError={(e) => { (e.target as HTMLImageElement).style.display = 'none' }}
                                />
                              </a>
                            ) : (
                              <div className="w-full h-20 bg-gray-100 rounded flex items-center justify-center">
                                <FileText className="w-6 h-6 text-gray-300" />
                              </div>
                            )}
                            <Badge status={doc.status} />
                          </div>
                        ))}
                        {(!d.documents || d.documents.length === 0) && (
                          <p className="text-sm text-gray-400 col-span-6">No documents uploaded</p>
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
        <Pager page={page} limit={LIMIT} total={total} onPage={setPage} noun={['application', 'applications']} />
      </div>

      {/* Approve confirmation modal */}
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

      {/* Reject with reason modal */}
      {rejectId && driverToReject && (
        <Modal title="Reject Application" onClose={() => { setRejectId(null); setRejectReason('') }} size="sm">
          <div>
            <div className="text-center mb-4">
              <XCircle className="w-12 h-12 text-red-500 mx-auto mb-3" />
              <p className="text-gray-700">Reject application for <strong>{driverToReject.name}</strong>?</p>
            </div>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-1">Rejection Reason</label>
              <textarea
                value={rejectReason}
                onChange={e => setRejectReason(e.target.value)}
                placeholder="Enter reason for rejection (optional)"
                rows={3}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-red-300 resize-none"
              />
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => { setRejectId(null); setRejectReason('') }}
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
