'use client'
import { useState, useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { Header } from '@/components/header'
import { Badge } from '@/components/ui/badge'
import { Toast } from '@/components/ui/toast'
import { ArrowLeft, Phone, Mail, Calendar, TrendingUp, Wallet, Car, Ban, Trash2, MapPin, CreditCard, User } from 'lucide-react'
import Link from 'next/link'

export default function UserDetailPage() {
  const { id } = useParams()
  const router = useRouter()
  const [user, setUser] = useState<any>(null)
  const [recentRides, setRecentRides] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [imgModal, setImgModal] = useState<string | null>(null)

  useEffect(() => {
    fetch(`/api/users/${id}`)
      .then(r => r.json())
      .then(d => { setUser(d.user); setRecentRides(d.recentRides || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [id])

  const totalSpent = recentRides.reduce((s: number, r: any) => s + (r.status === 'completed' ? (r.fare || 0) : 0), 0)

  const toggleBlock = async () => {
    const newStatus = user.status === 'active' ? 'blocked' : 'active'
    const res = await fetch(`/api/users/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: newStatus }),
    })
    if (res.ok) {
      setUser((u: any) => ({ ...u, status: newStatus }))
      setToast({ msg: `User ${newStatus}`, type: 'success' })
    }
  }

  const deleteUser = async () => {
    if (!confirm(`Delete this user? This cannot be undone.`)) return
    const res = await fetch(`/api/users/${id}`, { method: 'DELETE' })
    if (res.ok) {
      setToast({ msg: 'User deleted', type: 'success' })
      setTimeout(() => router.push('/users'), 1000)
    }
  }

  if (loading) return (
    <div>
      <Header title="User Profile" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  if (!user) return (
    <div>
      <Header title="User Not Found" />
      <div className="p-6"><p className="text-gray-500">User not found.</p></div>
    </div>
  )

  const fields = [
    { icon: User,       label: 'Full Name',    value: user.name },
    { icon: Phone,      label: 'Phone',        value: user.phone },
    { icon: Mail,       label: 'Email',        value: user.email },
    { icon: MapPin,     label: 'City',         value: user.city },
    { icon: CreditCard, label: 'ID Number',    value: user.idNumber },
    { icon: Calendar,   label: 'Joined',       value: user.createdAt ? new Date(user.createdAt).toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' }) : '—' },
  ]

  return (
    <div>
      <Header title="User Profile" />
      <div className="p-6 space-y-6">
        {/* Back + title */}
        <div className="flex items-center gap-3">
          <Link href="/users" className="p-2 hover:bg-gray-100 rounded-lg text-gray-600">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <h1 className="text-xl font-bold text-gray-900">User Profile</h1>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">

          {/* ── Left: profile card ── */}
          <div className="space-y-4">

            {/* Profile photo + basic info */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
              <div className="text-center mb-5">
                {user.profilePicUrl ? (
                  <img
                    src={`http://localhost:3000${user.profilePicUrl}`}
                    alt="Profile"
                    className="w-24 h-24 rounded-full object-cover mx-auto mb-3 border-4 border-blue-100 cursor-pointer hover:opacity-90"
                    onClick={() => setImgModal(`http://localhost:3000${user.profilePicUrl}`)}
                  />
                ) : (
                  <div className="w-24 h-24 rounded-full bg-blue-100 flex items-center justify-center text-blue-700 font-bold text-4xl mx-auto mb-3">
                    {user.name?.charAt(0)?.toUpperCase() || '?'}
                  </div>
                )}
                <h2 className="text-lg font-bold text-gray-900">{user.name || 'No name yet'}</h2>
                <Badge status={user.status} className="mt-2" />
              </div>

              {/* All signup fields */}
              <div className="space-y-3">
                {fields.map(({ icon: Icon, label, value }) => value ? (
                  <div key={label} className="flex items-start gap-3 text-sm">
                    <Icon className="w-4 h-4 text-gray-400 mt-0.5 flex-shrink-0" />
                    <div>
                      <p className="text-xs text-gray-400">{label}</p>
                      <p className="text-gray-800 font-medium">{value}</p>
                    </div>
                  </div>
                ) : null)}
              </div>

              {/* Actions */}
              <div className="mt-5 space-y-2">
                <button
                  type="button"
                  onClick={toggleBlock}
                  className={`w-full flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-medium ${
                    user.status === 'active'
                      ? 'bg-red-50 text-red-600 hover:bg-red-100 border border-red-200'
                      : 'bg-green-50 text-green-700 hover:bg-green-100 border border-green-200'
                  }`}
                >
                  <Ban className="w-4 h-4" />
                  {user.status === 'active' ? 'Block User' : 'Unblock User'}
                </button>
                <button
                  type="button"
                  onClick={deleteUser}
                  className="w-full flex items-center justify-center gap-2 py-2 rounded-lg text-sm font-medium bg-red-600 text-white hover:bg-red-700"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete User
                </button>
              </div>
            </div>

            {/* ID Proof image */}
            {user.idPhotoUrl && (
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-4">
                <p className="text-sm font-semibold text-gray-700 mb-3">ID Proof</p>
                <img
                  src={`http://localhost:3000${user.idPhotoUrl}`}
                  alt="ID Proof"
                  className="w-full rounded-lg object-cover cursor-pointer hover:opacity-90 border border-gray-100"
                  onClick={() => setImgModal(`http://localhost:3000${user.idPhotoUrl}`)}
                />
                <p className="text-xs text-gray-400 mt-2 text-center">Click to enlarge</p>
              </div>
            )}
          </div>

          {/* ── Right: stats + rides ── */}
          <div className="lg:col-span-2 space-y-4">

            {/* Stats cards */}
            <div className="grid grid-cols-3 gap-4">
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
                <Car className="w-7 h-7 text-blue-600 mb-2" />
                <p className="text-2xl font-bold text-gray-900">{user.totalRides || 0}</p>
                <p className="text-xs text-gray-500 mt-1">Total Rides</p>
              </div>
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
                <TrendingUp className="w-7 h-7 text-green-600 mb-2" />
                <p className="text-2xl font-bold text-gray-900">₹{totalSpent.toLocaleString()}</p>
                <p className="text-xs text-gray-500 mt-1">Total Spent</p>
              </div>
              <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
                <Wallet className="w-7 h-7 text-purple-600 mb-2" />
                <p className="text-2xl font-bold text-gray-900">₹{user.walletBalance || 0}</p>
                <p className="text-xs text-gray-500 mt-1">Wallet Balance</p>
              </div>
            </div>

            {/* Recent rides */}
            <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-5">
              <h3 className="font-semibold text-gray-800 mb-4">Recent Rides</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-100">
                      {['Route', 'Service', 'Fare', 'Payment', 'Status', 'Date'].map(h => (
                        <th key={h} className="text-left text-xs text-gray-500 font-semibold pb-3">{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-50">
                    {recentRides.map((r: any) => (
                      <tr key={r._id} className="hover:bg-gray-50">
                        <td className="py-2.5 text-gray-500 text-xs max-w-[180px] truncate">{r.pickupAddress} → {r.dropAddress}</td>
                        <td className="py-2.5 text-gray-600 capitalize">{r.service}</td>
                        <td className="py-2.5 font-medium">₹{r.fare}</td>
                        <td className="py-2.5 text-gray-500 capitalize">{r.paymentMode}</td>
                        <td className="py-2.5"><Badge status={r.status} /></td>
                        <td className="py-2.5 text-gray-500 text-xs">{r.createdAt ? new Date(r.createdAt).toLocaleDateString() : '—'}</td>
                      </tr>
                    ))}
                    {recentRides.length === 0 && (
                      <tr><td colSpan={6} className="text-center text-gray-400 py-8">No rides yet</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Image lightbox */}
      {imgModal && (
        <div
          className="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-4"
          onClick={() => setImgModal(null)}
        >
          <img src={imgModal} alt="Preview" className="max-w-full max-h-full rounded-xl object-contain" />
          <button type="button" className="absolute top-4 right-4 text-white text-3xl font-bold" onClick={() => setImgModal(null)}>×</button>
        </div>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
