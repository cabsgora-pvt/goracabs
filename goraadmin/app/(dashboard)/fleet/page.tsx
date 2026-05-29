'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus } from 'lucide-react'

export default function FleetPage() {
  const [fleet, setFleet] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState({ name: '', phone: '', email: '', commissionPercent: 20 })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchFleet = () => {
    fetch('/api/fleet')
      .then(r => r.json())
      .then(d => { setFleet(d.fleet || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchFleet() }, [])

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    const res = await fetch('/api/fleet', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
    if (res.ok) {
      fetchFleet()
      setShowModal(false)
      setForm({ name: '', phone: '', email: '', commissionPercent: 20 })
      setToast({ msg: 'Fleet owner added successfully', type: 'success' })
    } else {
      const d = await res.json()
      setToast({ msg: d.error || 'Failed to add', type: 'error' })
    }
  }

  return (
    <div>
      <Header title="Fleet Owners" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Fleet Owners"
          subtitle="Manage fleet owners and their vehicles"
          action={
            <button type="button" onClick={() => setShowModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Fleet Owner
            </button>
          }
        />

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  {['Owner Name', 'Phone', 'Email', 'Total Vehicles', 'Total Drivers', 'Commission %', 'Status'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {fleet.map(f => (
                  <tr key={f._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-purple-100 flex items-center justify-center text-purple-700 font-semibold text-xs flex-shrink-0">
                          {f.name?.charAt(0) || '?'}
                        </div>
                        <span className="font-medium text-gray-800">{f.name}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-600">{f.phone}</td>
                    <td className="px-4 py-3 text-gray-600">{f.email}</td>
                    <td className="px-4 py-3 font-semibold text-gray-800">{f.totalVehicles || 0}</td>
                    <td className="px-4 py-3 font-semibold text-gray-800">{f.totalDrivers || 0}</td>
                    <td className="px-4 py-3 font-semibold text-blue-700">{f.commissionPercent}%</td>
                    <td className="px-4 py-3"><Badge status={f.status} /></td>
                  </tr>
                ))}
                {fleet.length === 0 && (
                  <tr><td colSpan={7} className="text-center text-gray-400 py-12">No fleet owners yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showModal && (
        <Modal title="Add Fleet Owner" onClose={() => setShowModal(false)}>
          <form onSubmit={handleAdd} className="space-y-4">
            <div>
              <label htmlFor="foName" className="block text-sm font-medium text-gray-700 mb-1">Company / Owner Name *</label>
              <input id="foName" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="foPhone" className="block text-sm font-medium text-gray-700 mb-1">Phone *</label>
              <input id="foPhone" required value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="foEmail" className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input id="foEmail" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="foCommission" className="block text-sm font-medium text-gray-700 mb-1">Commission % *</label>
              <input id="foCommission" type="number" min="0" max="100" required value={form.commissionPercent}
                onChange={e => setForm({ ...form, commissionPercent: +e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Add</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
