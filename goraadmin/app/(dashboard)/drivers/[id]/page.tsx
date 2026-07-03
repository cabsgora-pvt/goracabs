'use client'
import { useState, useEffect } from 'react'
import { useParams } from 'next/navigation'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import {
  ArrowLeft, Phone, Car, Star, TrendingUp, DollarSign,
  CheckCircle, XCircle, Mail, MapPin, CreditCard, FileText,
  Trash2, Ban, CalendarClock, ArrowDownToLine, SlidersHorizontal,
} from 'lucide-react'
import Link from 'next/link'

export default function DriverDetailPage() {
  const { id } = useParams()
  const [driver, setDriver] = useState<any>(null)
  const [recentRides, setRecentRides] = useState<any[]>([])
  const [subs, setSubs] = useState<any[]>([])
  const [withdrawals, setWithdrawals] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [rejectModal, setRejectModal] = useState(false)
  const [rejectReason, setRejectReason] = useState('')
  const [deleteModal, setDeleteModal] = useState(false)
  const [actionLoading, setActionLoading] = useState(false)
  const [wAmount, setWAmount] = useState('')
  const [wType, setWType] = useState<'credit' | 'debit'>('credit')
  const [wNote, setWNote] = useState('')
  const [wBusy, setWBusy] = useState(false)
  const [allowTaxi, setAllowTaxi] = useState(true)
  const [allowRental, setAllowRental] = useState(true)
  const [allowOutstation, setAllowOutstation] = useState(true)
  const [allowHireDriver, setAllowHireDriver] = useState(true)
  const [allowDelivery, setAllowDelivery] = useState(true)
  const [prefsBusy, setPrefsBusy] = useState(false)
  const [photoBusy, setPhotoBusy] = useState(false)

  const fetchDriver = () => {
    fetch(`/api/drivers/${id}`)
      .then(r => r.json())
      .then(d => { setDriver(d.driver); setRecentRides(d.recentRides || []); setSubs(d.subscriptions || []); setWithdrawals(d.withdrawals || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchDriver() }, [id])

  useEffect(() => {
    if (!driver) return
    setAllowTaxi(driver.allowTaxi !== false)
    setAllowRental(driver.allowRental !== false)
    setAllowOutstation(driver.allowOutstation !== false)
    setAllowHireDriver(driver.allowHireDriver !== false)
    setAllowDelivery(driver.allowDelivery !== false)
  }, [driver])

  const saveServicePreferences = async () => {
    setPrefsBusy(true)
    try {
      const res = await fetch(`/api/drivers/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ allowTaxi, allowRental, allowOutstation, allowHireDriver, allowDelivery }),
      })
      if (res.ok) {
        fetchDriver()
        setToast({ msg: 'Service preferences saved', type: 'success' })
      } else {
        setToast({ msg: 'Failed to save service preferences', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to save service preferences', type: 'error' })
    }
    setPrefsBusy(false)
  }

  const uploadPhoto = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    setPhotoBusy(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const upRes = await fetch('/api/upload', { method: 'POST', body: fd })
      const upData = await upRes.json()
      if (!upRes.ok || !upData.url) {
        setToast({ msg: upData.error || 'Failed to upload photo', type: 'error' })
        setPhotoBusy(false)
        return
      }
      const putRes = await fetch(`/api/drivers/${id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ profilePicUrl: upData.url }),
      })
      if (putRes.ok) {
        fetchDriver()
        setToast({ msg: 'Profile photo updated', type: 'success' })
      } else {
        setToast({ msg: 'Failed to save profile photo', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to update profile photo', type: 'error' })
    }
    setPhotoBusy(false)
  }

  const approveDriver = async () => {
    setActionLoading(true)
    const res = await fetch(`/api/drivers/${id}/approve`, { method: 'POST' })
    if (res.ok) {
      setDriver((d: any) => ({ ...d, status: 'approved' }))
      setToast({ msg: 'Driver approved!', type: 'success' })
    }
    setActionLoading(false)
  }

  const rejectDriver = async () => {
    setActionLoading(true)
    const res = await fetch(`/api/drivers/${id}/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: rejectReason || 'Rejected by admin' }),
    })
    if (res.ok) {
      setDriver((d: any) => ({ ...d, status: 'rejected', rejectionReason: rejectReason }))
      setRejectModal(false)
      setRejectReason('')
      setToast({ msg: 'Driver rejected', type: 'error' })
    }
    setActionLoading(false)
  }

  const blockDriver = async () => {
    setActionLoading(true)
    const patchRes = await fetch(`/api/drivers/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'blocked' }),
    })
    if (patchRes.ok) {
      setDriver((d: any) => ({ ...d, status: 'blocked' }))
      setToast({ msg: 'Driver blocked', type: 'error' })
    }
    setActionLoading(false)
  }

  const deleteDriver = async () => {
    setActionLoading(true)
    const res = await fetch(`/api/drivers/${id}`, { method: 'DELETE' })
    if (res.ok) {
      setToast({ msg: 'Driver deleted', type: 'error' })
      setTimeout(() => window.location.href = '/drivers', 1200)
    }
    setActionLoading(false)
    setDeleteModal(false)
  }

  const adjustWallet = async () => {
    const amount = Number(wAmount)
    if (!amount || amount <= 0) {
      setToast({ msg: 'Enter a valid amount', type: 'error' })
      return
    }
    setWBusy(true)
    try {
      const res = await fetch(`/api/drivers/${id}/wallet`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ amount, type: wType, note: wNote }),
      })
      const d = await res.json()
      if (res.ok && d.success) {
        setWAmount('')
        setWNote('')
        fetchDriver()
        setToast({ msg: `Wallet ${wType === 'credit' ? 'credited' : 'debited'}`, type: 'success' })
      } else {
        setToast({ msg: d.error || 'Failed to adjust wallet', type: 'error' })
      }
    } catch {
      setToast({ msg: 'Failed to adjust wallet', type: 'error' })
    }
    setWBusy(false)
  }

  const verifyDoc = async (docId: string) => {
    const res = await fetch(`/api/drivers/${id}/documents/${docId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'verified' }),
    })
    if (res.ok) {
      const d = await res.json()
      setDriver(d.driver)
      setToast({ msg: 'Document verified', type: 'success' })
    }
  }

  const rejectDoc = async (docId: string) => {
    const res = await fetch(`/api/drivers/${id}/documents/${docId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'rejected' }),
    })
    if (res.ok) {
      const d = await res.json()
      setDriver(d.driver)
      setToast({ msg: 'Document rejected', type: 'error' })
    }
  }

  if (loading) return (
    <div><Header title="Driver Profile" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  if (!driver) return (
    <div><Header title="Driver Not Found" />
      <div className="p-6"><p className="text-gray-500">Driver not found.</p></div>
    </div>
  )

  return (
    <div>
      <Header title="Driver Profile" />
      <div className="p-6 space-y-6">
        <div className="flex items-center gap-3">
          <Link href="/drivers" className="p-2 hover:bg-gray-100 rounded-lg text-gray-600">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <h1 className="text-xl font-bold text-gray-900">Driver Profile</h1>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Profile Card */}
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
            <div className="text-center mb-6">
              {driver.profilePicUrl ? (
                <img
                  src={driver.profilePicUrl}
                  alt={driver.name || 'Driver'}
                  className="w-20 h-20 rounded-full object-cover mx-auto mb-3"
                />
              ) : (
                <div className="w-20 h-20 rounded-full bg-green-100 flex items-center justify-center text-green-700 font-bold text-3xl mx-auto mb-3">
                  {driver.name?.charAt(0) || '?'}
                </div>
              )}
              <div className="mb-3">
                <input
                  id="driver-photo-input"
                  type="file"
                  accept="image/*"
                  onChange={uploadPhoto}
                  aria-label="Choose profile photo"
                  title="Choose profile photo"
                  className="hidden"
                />
                <label
                  htmlFor="driver-photo-input"
                  className={`inline-flex items-center gap-1 px-3 py-1.5 bg-gray-50 text-gray-700 rounded-lg text-xs font-medium border border-gray-200 hover:bg-gray-100 cursor-pointer ${photoBusy ? 'opacity-50 pointer-events-none' : ''}`}>
                  {photoBusy ? 'Uploading…' : 'Change Photo'}
                </label>
              </div>
              <h2 className="text-lg font-bold text-gray-900">{driver.name || 'Unnamed'}</h2>
              <div className="mt-2"><Badge status={driver.status} /></div>
              {driver.rejectionReason && (
                <p className="mt-2 text-xs text-red-500 bg-red-50 rounded px-2 py-1">
                  Reason: {driver.rejectionReason}
                </p>
              )}
            </div>
            <div className="space-y-3">
              <div className="flex items-center gap-3 text-sm">
                <Phone className="w-4 h-4 text-gray-400" />
                <span className="text-gray-700">{driver.phone}</span>
              </div>
              {driver.email && (
                <div className="flex items-center gap-3 text-sm">
                  <Mail className="w-4 h-4 text-gray-400" />
                  <span className="text-gray-700">{driver.email}</span>
                </div>
              )}
              {(driver.state || driver.zoneName) && (
                <div className="flex items-center gap-3 text-sm">
                  <MapPin className="w-4 h-4 text-gray-400" />
                  <span className="text-gray-700">{[driver.zoneName, driver.state].filter(Boolean).join(', ')}</span>
                </div>
              )}
              <div className="flex items-center gap-3 text-sm">
                <Car className="w-4 h-4 text-gray-400" />
                <div>
                  <p className="text-gray-700 font-mono">{driver.vehicleRegistrationNumber || driver.vehicleNumber || '—'}</p>
                  <p className="text-gray-500 text-xs">{driver.selectedVehicleTypeName || driver.vehicleType || '—'} • {driver.vehicleModel || '—'}</p>
                </div>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Star className="w-4 h-4 text-yellow-400 fill-yellow-400" />
                <span className="text-gray-700">{driver.rating > 0 ? driver.rating : 'No ratings yet'}</span>
              </div>
            </div>

            {/* Action buttons */}
            <div className="mt-5 space-y-2">
              {driver.status === 'pending' && (
                <div className="flex gap-2">
                  <button type="button" onClick={approveDriver} disabled={actionLoading}
                    className="flex-1 flex items-center justify-center gap-1 py-2 bg-green-50 text-green-700 rounded-lg text-sm font-medium hover:bg-green-100 border border-green-200 disabled:opacity-50">
                    <CheckCircle className="w-4 h-4" /> Approve
                  </button>
                  <button type="button" onClick={() => setRejectModal(true)} disabled={actionLoading}
                    className="flex-1 flex items-center justify-center gap-1 py-2 bg-red-50 text-red-600 rounded-lg text-sm font-medium hover:bg-red-100 border border-red-200 disabled:opacity-50">
                    <XCircle className="w-4 h-4" /> Reject
                  </button>
                </div>
              )}
              {driver.status === 'approved' && (
                <button type="button" onClick={blockDriver} disabled={actionLoading}
                  className="w-full flex items-center justify-center gap-1 py-2 bg-orange-50 text-orange-600 rounded-lg text-sm font-medium hover:bg-orange-100 border border-orange-200 disabled:opacity-50">
                  <Ban className="w-4 h-4" /> Block Driver
                </button>
              )}
              <button type="button" onClick={() => setDeleteModal(true)} disabled={actionLoading}
                className="w-full flex items-center justify-center gap-1 py-2 bg-red-50 text-red-600 rounded-lg text-sm font-medium hover:bg-red-100 border border-red-200 disabled:opacity-50">
                <Trash2 className="w-4 h-4" /> Delete Driver
              </button>
            </div>
          </div>

          {/* Right column */}
          <div className="lg:col-span-2 space-y-4">
            {/* Stats */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 text-center">
                <Star className="w-6 h-6 text-yellow-400 fill-yellow-400 mx-auto mb-1" />
                <p className="text-xl font-bold text-gray-900">{driver.rating || '—'}</p>
                <p className="text-xs text-gray-500 mt-1">Rating</p>
              </div>
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 text-center">
                <Car className="w-6 h-6 text-blue-600 mx-auto mb-1" />
                <p className="text-xl font-bold text-gray-900">{driver.totalRides || 0}</p>
                <p className="text-xs text-gray-500 mt-1">Total Rides</p>
              </div>
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 text-center">
                <TrendingUp className="w-6 h-6 text-green-600 mx-auto mb-1" />
                <p className="text-xl font-bold text-gray-900">₹{(driver.totalEarnings || 0).toLocaleString()}</p>
                <p className="text-xs text-gray-500 mt-1">Total Earnings</p>
              </div>
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4 text-center">
                <DollarSign className="w-6 h-6 text-purple-600 mx-auto mb-1" />
                <p className="text-xl font-bold text-gray-900">₹{(driver.walletBalance || 0).toLocaleString()}</p>
                <p className="text-xs text-gray-500 mt-1">Wallet</p>
              </div>
            </div>

            {/* Adjust Wallet */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <DollarSign className="w-4 h-4" /> Adjust Wallet
              </h3>
              <div className="flex flex-col sm:flex-row sm:items-center gap-2">
                <div className="flex rounded-lg border border-gray-200 overflow-hidden">
                  <button
                    type="button"
                    onClick={() => setWType('credit')}
                    aria-label="Add money (credit)"
                    title="Add money (credit)"
                    className={`px-3 py-2 text-sm font-medium ${wType === 'credit' ? 'bg-green-50 text-green-700' : 'bg-white text-gray-500 hover:bg-gray-50'}`}>
                    Add
                  </button>
                  <button
                    type="button"
                    onClick={() => setWType('debit')}
                    aria-label="Deduct money (debit)"
                    title="Deduct money (debit)"
                    className={`px-3 py-2 text-sm font-medium border-l border-gray-200 ${wType === 'debit' ? 'bg-red-50 text-red-600' : 'bg-white text-gray-500 hover:bg-gray-50'}`}>
                    Deduct
                  </button>
                </div>
                <input
                  type="number"
                  min="0"
                  value={wAmount}
                  onChange={e => setWAmount(e.target.value)}
                  placeholder="Amount ₹"
                  aria-label="Wallet adjustment amount"
                  title="Wallet adjustment amount"
                  className="w-32 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-purple-300"
                />
                <input
                  type="text"
                  value={wNote}
                  onChange={e => setWNote(e.target.value)}
                  placeholder="Note (optional)"
                  aria-label="Wallet adjustment note"
                  title="Wallet adjustment note"
                  className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-purple-300"
                />
                <button
                  type="button"
                  onClick={adjustWallet}
                  disabled={wBusy}
                  aria-label="Apply wallet adjustment"
                  title="Apply wallet adjustment"
                  className="px-4 py-2 bg-purple-600 text-white rounded-lg text-sm font-medium hover:bg-purple-700 disabled:opacity-50">
                  {wBusy ? 'Applying…' : 'Apply'}
                </button>
              </div>
            </div>

            {/* Service Preferences */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <SlidersHorizontal className="w-4 h-4" /> Service Preferences
              </h3>

              {/* Currently accepting */}
              <div className="mb-4">
                <p className="text-xs text-gray-500 mb-2">Currently accepting:</p>
                <div className="flex flex-wrap gap-2">
                  {[
                    { label: 'Taxi', accepted: true },
                    { label: 'Rental', accepted: !!driver.acceptsRental },
                    { label: 'Outstation', accepted: !!driver.acceptsOutstation },
                    { label: 'Hire Driver', accepted: !!driver.acceptsHireDriver },
                    { label: 'Delivery', accepted: !!driver.acceptsDelivery },
                  ].map(s => (
                    <span
                      key={s.label}
                      className={`inline-block px-2.5 py-1 rounded-full text-xs font-medium ${
                        s.accepted ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-400'
                      }`}>
                      {s.label}
                    </span>
                  ))}
                </div>
              </div>

              {/* Allowed services */}
              <div className="border-t border-gray-100 pt-4">
                <p className="text-sm font-medium text-gray-700 mb-1">Allowed services</p>
                <p className="text-xs text-gray-500 mb-3">Unchecked services are hidden in the driver app and cannot be enabled.</p>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {[
                    { label: 'Taxi', value: allowTaxi, set: setAllowTaxi },
                    { label: 'Rental', value: allowRental, set: setAllowRental },
                    { label: 'Outstation', value: allowOutstation, set: setAllowOutstation },
                    { label: 'Hire Driver', value: allowHireDriver, set: setAllowHireDriver },
                    { label: 'Delivery', value: allowDelivery, set: setAllowDelivery },
                  ].map(s => (
                    <label key={s.label} className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={s.value}
                        onChange={e => s.set(e.target.checked)}
                        aria-label={`Allow ${s.label}`}
                        title={`Allow ${s.label}`}
                        className="w-4 h-4 rounded border-gray-300 text-green-600 focus:ring-green-300"
                      />
                      {s.label}
                    </label>
                  ))}
                </div>
                <div className="mt-4">
                  <button
                    type="button"
                    onClick={saveServicePreferences}
                    disabled={prefsBusy}
                    aria-label="Save service preferences"
                    title="Save service preferences"
                    className="px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 disabled:opacity-50">
                    {prefsBusy ? 'Saving…' : 'Save'}
                  </button>
                </div>
              </div>
            </div>

            {/* Bank Details */}
            {driver.bankDetails?.accountNumber && (
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
                <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                  <CreditCard className="w-4 h-4" /> Bank Details
                </h3>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
                  <div><p className="text-xs text-gray-500">Account Holder</p><p className="font-medium">{driver.bankDetails.accountHolderName}</p></div>
                  <div><p className="text-xs text-gray-500">Bank Name</p><p className="font-medium">{driver.bankDetails.bankName}</p></div>
                  <div><p className="text-xs text-gray-500">Branch</p><p className="font-medium">{driver.bankDetails.branch || '—'}</p></div>
                  <div><p className="text-xs text-gray-500">Account Number</p><p className="font-mono font-medium">{'••••' + driver.bankDetails.accountNumber.slice(-4)}</p></div>
                  <div><p className="text-xs text-gray-500">IFSC Code</p><p className="font-mono font-medium">{driver.bankDetails.ifscCode}</p></div>
                  <div><p className="text-xs text-gray-500">Account Type</p><p className="font-medium capitalize">{driver.bankDetails.accountType || 'savings'}</p></div>
                </div>
              </div>
            )}

            {/* Subscription */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <CalendarClock className="w-4 h-4" /> Subscription
              </h3>

              {/* Current status */}
              {driver.subscriptionActive ? (
                <div className="rounded-lg border border-green-200 bg-green-50 p-4 mb-4">
                  <p className="text-sm font-semibold text-green-800">Active: {driver.subscriptionPlanName || '—'}</p>
                  <p className="text-xs text-green-700 mt-1">
                    Expires: {driver.subscriptionExpiresAt ? new Date(driver.subscriptionExpiresAt).toLocaleDateString() : '—'}
                  </p>
                  <p className="text-xs text-green-700 mt-1">
                    Commission while active: {driver.subscriptionCommissionPercent ?? 0}%
                  </p>
                </div>
              ) : (
                <div className="rounded-lg border border-gray-200 bg-gray-50 p-4 mb-4">
                  <p className="text-sm text-gray-600">No active subscription — pays normal commission</p>
                </div>
              )}

              {/* Recent plans */}
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100">
                      {['Plan', 'Price', 'Duration', 'Started', 'Expires', 'Status'].map(h => (
                        <th key={h} className="text-left text-xs text-gray-500 font-semibold pb-3">{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {subs.map((s: any, i: number) => (
                      <tr key={i} className="hover:bg-gray-50">
                        <td className="py-2.5 text-gray-700">{s.planName || '—'}</td>
                        <td className="py-2.5 font-medium">₹{(s.price || 0).toLocaleString()}</td>
                        <td className="py-2.5 text-gray-500 text-xs">{s.durationDays ?? '—'} days</td>
                        <td className="py-2.5 text-gray-500 text-xs">{s.startedAt ? new Date(s.startedAt).toLocaleDateString() : '—'}</td>
                        <td className="py-2.5 text-gray-500 text-xs">{s.expiresAt ? new Date(s.expiresAt).toLocaleDateString() : '—'}</td>
                        <td className="py-2.5">
                          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                            s.status === 'active' ? 'bg-green-100 text-green-700'
                              : s.status === 'cancelled' ? 'bg-red-100 text-red-600'
                              : 'bg-gray-100 text-gray-600'
                          }`}>
                            {s.status || 'expired'}
                          </span>
                        </td>
                      </tr>
                    ))}
                    {subs.length === 0 && (
                      <tr><td colSpan={6} className="text-center text-gray-400 py-8">No subscription history</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Withdrawal History */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <ArrowDownToLine className="w-4 h-4" /> Withdrawal History
              </h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100">
                      {['Date', 'Amount', 'Bank', 'Status', 'Note/Reason'].map(h => (
                        <th key={h} className="text-left text-xs text-gray-500 font-semibold pb-3">{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {withdrawals.map((w: any, i: number) => (
                      <tr key={w._id || i} className="hover:bg-gray-50">
                        <td className="py-2.5 text-gray-500 text-xs">{w.createdAt ? new Date(w.createdAt).toLocaleDateString() : '—'}</td>
                        <td className="py-2.5 font-medium">₹{(w.amount || 0).toLocaleString()}</td>
                        <td className="py-2.5 text-gray-700">
                          {w.bankName || '—'}
                          {w.accountNumber && (
                            <span className="text-gray-400 font-mono text-xs ml-1">•••• {String(w.accountNumber).slice(-4)}</span>
                          )}
                        </td>
                        <td className="py-2.5">
                          <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                            w.status === 'approved' ? 'bg-green-100 text-green-700'
                              : w.status === 'rejected' ? 'bg-red-100 text-red-600'
                              : 'bg-yellow-100 text-yellow-700'
                          }`}>
                            {w.status || 'pending'}
                          </span>
                        </td>
                        <td className="py-2.5 text-gray-500 text-xs">{w.note || '—'}</td>
                      </tr>
                    ))}
                    {withdrawals.length === 0 && (
                      <tr><td colSpan={5} className="text-center text-gray-400 py-8">No withdrawals yet</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Documents */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <FileText className="w-4 h-4" /> Documents
              </h3>
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
                {(driver.documents || []).map((doc: any) => (
                  <div key={doc._id} className="border border-gray-200 rounded-lg overflow-hidden">
                    {doc.fileUrl ? (
                      <a href={doc.fileUrl} target="_blank" rel="noopener noreferrer" className="block">
                        <img
                          src={doc.fileUrl}
                          alt={doc.name}
                          className="w-full h-28 object-cover"
                          onError={(e) => {
                            const el = e.target as HTMLImageElement
                            el.parentElement!.innerHTML = '<div class="w-full h-28 bg-gray-100 flex items-center justify-center text-gray-300 text-xs">No preview</div>'
                          }}
                        />
                      </a>
                    ) : (
                      <div className="w-full h-28 bg-gray-100 flex items-center justify-center">
                        <FileText className="w-8 h-8 text-gray-300" />
                      </div>
                    )}
                    <div className="p-2">
                      <p className="text-xs font-medium text-gray-800 mb-1">{doc.name}</p>
                      <div className="flex items-center justify-between">
                        <Badge status={doc.status} />
                        <div className="flex gap-1">
                          {doc.status !== 'verified' && (
                            <button type="button" onClick={() => verifyDoc(doc._id)}
                              title="Verify"
                              className="p-1 bg-green-50 text-green-700 rounded hover:bg-green-100 border border-green-200">
                              <CheckCircle className="w-3 h-3" />
                            </button>
                          )}
                          {doc.status !== 'rejected' && (
                            <button type="button" onClick={() => rejectDoc(doc._id)}
                              title="Reject"
                              className="p-1 bg-red-50 text-red-600 rounded hover:bg-red-100 border border-red-200">
                              <XCircle className="w-3 h-3" />
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
                {(!driver.documents || driver.documents.length === 0) && (
                  <p className="text-sm text-gray-400 col-span-3">No documents uploaded</p>
                )}
              </div>
            </div>

            {/* Recent trips */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4">Recent Trips</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100">
                      {['Rider', 'Route', 'Fare', 'Status', 'Date'].map(h => (
                        <th key={h} className="text-left text-xs text-gray-500 font-semibold pb-3">{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {recentRides.map((r: any) => (
                      <tr key={r._id} className="hover:bg-gray-50">
                        <td className="py-2.5 text-gray-700">{r.riderName}</td>
                        <td className="py-2.5 text-gray-500 text-xs">{r.pickupAddress} → {r.dropAddress}</td>
                        <td className="py-2.5 font-medium">₹{r.fare}</td>
                        <td className="py-2.5"><Badge status={r.status} /></td>
                        <td className="py-2.5 text-gray-500 text-xs">{r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'}</td>
                      </tr>
                    ))}
                    {recentRides.length === 0 && (
                      <tr><td colSpan={5} className="text-center text-gray-400 py-8">No trips yet</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Reject modal */}
      {rejectModal && (
        <Modal title="Reject Driver" onClose={() => { setRejectModal(false); setRejectReason('') }} size="sm">
          <div>
            <div className="text-center mb-4">
              <XCircle className="w-12 h-12 text-red-500 mx-auto mb-2" />
              <p className="text-gray-700">Reject driver <strong>{driver.name}</strong>?</p>
            </div>
            <div className="mb-4">
              <label className="block text-sm font-medium text-gray-700 mb-1">Rejection Reason</label>
              <textarea
                value={rejectReason}
                onChange={e => setRejectReason(e.target.value)}
                placeholder="Enter reason for rejection"
                rows={3}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-red-300 resize-none"
              />
            </div>
            <div className="flex gap-3">
              <button type="button" onClick={() => { setRejectModal(false); setRejectReason('') }}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="button" onClick={rejectDriver} disabled={actionLoading}
                className="flex-1 bg-red-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-red-700 disabled:opacity-50">Reject</button>
            </div>
          </div>
        </Modal>
      )}

      {/* Delete confirmation modal */}
      {deleteModal && (
        <Modal title="Delete Driver" onClose={() => setDeleteModal(false)} size="sm">
          <div className="text-center">
            <Trash2 className="w-12 h-12 text-red-500 mx-auto mb-3" />
            <p className="text-gray-700 font-semibold">Delete driver <strong>{driver.name}</strong>?</p>
            <p className="text-gray-500 text-sm mt-1">This action cannot be undone.</p>
            <div className="flex gap-3 mt-5">
              <button type="button" onClick={() => setDeleteModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="button" onClick={deleteDriver} disabled={actionLoading}
                className="flex-1 bg-red-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-red-700 disabled:opacity-50">Delete</button>
            </div>
          </div>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
