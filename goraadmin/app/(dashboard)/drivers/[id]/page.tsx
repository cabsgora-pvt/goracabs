'use client'
import { useState, useEffect } from 'react'
import { useParams } from 'next/navigation'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { ArrowLeft, Phone, Car, Star, TrendingUp, DollarSign, CheckCircle, XCircle } from 'lucide-react'
import Link from 'next/link'

export default function DriverDetailPage() {
  const { id } = useParams()
  const [driver, setDriver] = useState<any>(null)
  const [recentRides, setRecentRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchDriver = () => {
    fetch(`/api/drivers/${id}`)
      .then(r => r.json())
      .then(d => { setDriver(d.driver); setRecentRides(d.recentRides || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchDriver() }, [id])

  const approveDriver = async () => {
    const res = await fetch(`/api/drivers/${id}/approve`, { method: 'POST' })
    if (res.ok) {
      setDriver((d: any) => ({ ...d, status: 'approved' }))
      setToast({ msg: 'Driver approved!', type: 'success' })
    }
  }

  const rejectDriver = async () => {
    const res = await fetch(`/api/drivers/${id}/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: 'Rejected by admin' }),
    })
    if (res.ok) {
      setDriver((d: any) => ({ ...d, status: 'rejected' }))
      setToast({ msg: 'Driver rejected', type: 'error' })
    }
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
          {/* Profile */}
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
            <div className="text-center mb-6">
              <div className="w-20 h-20 rounded-full bg-green-100 flex items-center justify-center text-green-700 font-bold text-3xl mx-auto mb-3">
                {driver.name?.charAt(0) || '?'}
              </div>
              <h2 className="text-lg font-bold text-gray-900">{driver.name}</h2>
              <Badge status={driver.status} className="mt-2" />
            </div>
            <div className="space-y-3">
              <div className="flex items-center gap-3 text-sm">
                <Phone className="w-4 h-4 text-gray-400" />
                <span className="text-gray-700">{driver.phone}</span>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Car className="w-4 h-4 text-gray-400" />
                <div>
                  <p className="text-gray-700 font-mono">{driver.vehicleNumber}</p>
                  <p className="text-gray-500 text-xs">{driver.vehicleType}</p>
                </div>
              </div>
              <div className="flex items-center gap-3 text-sm">
                <Star className="w-4 h-4 text-yellow-400 fill-yellow-400" />
                <span className="text-gray-700">{driver.rating > 0 ? driver.rating : 'No ratings yet'}</span>
              </div>
            </div>
            {driver.status === 'pending' && (
              <div className="mt-5 flex gap-2">
                <button type="button" onClick={approveDriver}
                  className="flex-1 flex items-center justify-center gap-1 py-2 bg-green-50 text-green-700 rounded-lg text-sm font-medium hover:bg-green-100 border border-green-200">
                  <CheckCircle className="w-4 h-4" /> Approve
                </button>
                <button type="button" onClick={rejectDriver}
                  className="flex-1 flex items-center justify-center gap-1 py-2 bg-red-50 text-red-600 rounded-lg text-sm font-medium hover:bg-red-100 border border-red-200">
                  <XCircle className="w-4 h-4" /> Reject
                </button>
              </div>
            )}
          </div>

          {/* Stats + Documents */}
          <div className="lg:col-span-2 space-y-4">
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

            {/* Documents */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4">Documents</h3>
              <div className="space-y-3">
                {(driver.documents || []).map((doc: any) => (
                  <div key={doc._id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                    <div>
                      <p className="text-sm font-medium text-gray-800">{doc.name}</p>
                      <Badge status={doc.status} />
                    </div>
                    <div className="flex gap-2">
                      {doc.status !== 'verified' && (
                        <button type="button" onClick={() => verifyDoc(doc._id)}
                          className="flex items-center gap-1 px-2 py-1 bg-green-50 text-green-700 rounded text-xs hover:bg-green-100 border border-green-200">
                          <CheckCircle className="w-3 h-3" /> Verify
                        </button>
                      )}
                      {doc.status !== 'rejected' && (
                        <button type="button" onClick={() => rejectDoc(doc._id)}
                          className="flex items-center gap-1 px-2 py-1 bg-red-50 text-red-600 rounded text-xs hover:bg-red-100 border border-red-200">
                          <XCircle className="w-3 h-3" /> Reject
                        </button>
                      )}
                    </div>
                  </div>
                ))}
                {(!driver.documents || driver.documents.length === 0) && (
                  <p className="text-sm text-gray-400">No documents uploaded</p>
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
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
