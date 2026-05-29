'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Users, UserCheck, UserX, UserPlus, Search, Eye, Ban, Trash2 } from 'lucide-react'

export default function UsersPage() {
  const [users, setUsers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [showAddModal, setShowAddModal] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' | 'info' } | null>(null)
  const [newUser, setNewUser] = useState({ name: '', phone: '', email: '' })

  const fetchUsers = () => {
    setLoading(true)
    const params = new URLSearchParams({ limit: '100' })
    if (statusFilter !== 'all') params.set('status', statusFilter)
    if (search) params.set('search', search)
    fetch(`/api/users?${params}`)
      .then(r => r.json())
      .then(d => { setUsers(d.users || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchUsers() }, [statusFilter])

  const filtered = users.filter(u => {
    if (!search) return true
    const s = search.toLowerCase()
    return u.name?.toLowerCase().includes(s) || u.email?.toLowerCase().includes(s) || u.phone?.includes(search)
  })

  const stats = {
    total: users.length,
    active: users.filter(u => u.status === 'active').length,
    blocked: users.filter(u => u.status === 'blocked').length,
  }

  const deleteUser = async (id: string, name: string) => {
    if (!confirm(`Delete user "${name}"? This cannot be undone.`)) return
    const res = await fetch(`/api/users/${id}`, { method: 'DELETE' })
    if (res.ok) {
      setUsers(prev => prev.filter(u => u._id !== id))
      setToast({ msg: 'User deleted', type: 'success' })
    }
  }

  const toggleBlock = async (id: string, current: string) => {
    const newStatus = current === 'active' ? 'blocked' : 'active'
    const res = await fetch(`/api/users/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: newStatus }),
    })
    if (res.ok) {
      setUsers(prev => prev.map(u => u._id === id ? { ...u, status: newStatus } : u))
      setToast({ msg: 'User status updated', type: 'success' })
    }
  }

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newUser.name || !newUser.phone || !newUser.email) {
      setToast({ msg: 'Please fill all required fields', type: 'error' })
      return
    }
    const res = await fetch('/api/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newUser),
    })
    if (res.ok) {
      setShowAddModal(false)
      setNewUser({ name: '', phone: '', email: '' })
      setToast({ msg: 'User added successfully', type: 'success' })
      fetchUsers()
    } else {
      const d = await res.json()
      setToast({ msg: d.error || 'Failed to add user', type: 'error' })
    }
  }

  return (
    <div>
      <Header title="Users" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Users"
          subtitle="Manage all registered users"
          action={
            <button
              type="button"
              onClick={() => setShowAddModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark"
            >
              <UserPlus className="w-4 h-4" /> Add User
            </button>
          }
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatsCard icon={Users} label="Total Users" value={stats.total} iconColor="text-blue-600" iconBg="bg-blue-50" />
          <StatsCard icon={UserCheck} label="Active" value={stats.active} iconColor="text-green-600" iconBg="bg-green-50" />
          <StatsCard icon={UserX} label="Blocked" value={stats.blocked} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={UserPlus} label="New Today" value={0} iconColor="text-purple-600" iconBg="bg-purple-50" />
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm">
          <div className="p-4 border-b border-gray-100 flex flex-wrap gap-3 items-center">
            <div className="flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 flex-1 min-w-48">
              <Search className="w-4 h-4 text-gray-400" />
              <input
                value={search}
                onChange={e => setSearch(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && fetchUsers()}
                placeholder="Search users..."
                className="bg-transparent text-sm outline-none w-full"
              />
            </div>
            <select
              aria-label="Filter by status"
              value={statusFilter}
              onChange={e => setStatusFilter(e.target.value)}
              className="border border-gray-200 rounded-lg px-3 py-2 text-sm text-gray-700 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">All Status</option>
              <option value="active">Active</option>
              <option value="blocked">Blocked</option>
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
                    {['User', 'Phone', 'Email', 'Total Rides', 'Wallet', 'Status', 'Join Date', 'Actions'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase tracking-wide px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {filtered.map(u => (
                    <tr key={u._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center text-blue-700 font-semibold text-xs">
                            {u.name?.charAt(0) || '?'}
                          </div>
                          <span className="font-medium text-gray-800">{u.name}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-gray-600">{u.phone}</td>
                      <td className="px-4 py-3 text-gray-600">{u.email}</td>
                      <td className="px-4 py-3 text-gray-800 font-medium">{u.totalRides || 0}</td>
                      <td className="px-4 py-3 text-gray-800">₹{u.walletBalance || 0}</td>
                      <td className="px-4 py-3"><Badge status={u.status} /></td>
                      <td className="px-4 py-3 text-gray-500">{u.createdAt ? new Date(u.createdAt).toLocaleDateString() : '—'}</td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <a href={`/users/${u._id}`} className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600" title="View">
                            <Eye className="w-4 h-4" />
                          </a>
                          <button
                            type="button"
                            onClick={() => toggleBlock(u._id, u.status)}
                            className={`p-1.5 rounded-lg ${u.status === 'active' ? 'hover:bg-red-50 text-red-500' : 'hover:bg-green-50 text-green-600'}`}
                            title={u.status === 'active' ? 'Block' : 'Unblock'}
                          >
                            <Ban className="w-4 h-4" />
                          </button>
                          <button
                            type="button"
                            onClick={() => deleteUser(u._id, u.name || u.phone)}
                            className="p-1.5 hover:bg-red-50 rounded-lg text-red-500"
                            title="Delete"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={8} className="text-center text-gray-400 py-12">No users found</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {showAddModal && (
        <Modal title="Add New User" onClose={() => setShowAddModal(false)}>
          <form onSubmit={handleAdd} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Full Name *</label>
              <input required value={newUser.name} onChange={e => setNewUser({ ...newUser, name: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" placeholder="Enter full name" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Phone *</label>
              <input required value={newUser.phone} onChange={e => setNewUser({ ...newUser, phone: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" placeholder="+91 XXXXX XXXXX" />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email *</label>
              <input required type="email" value={newUser.email} onChange={e => setNewUser({ ...newUser, email: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" placeholder="user@example.com" />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowAddModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Add User</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
