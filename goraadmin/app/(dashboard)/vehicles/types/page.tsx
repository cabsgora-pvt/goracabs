'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { PageHeader } from '@/components/ui/page-header'
import { Plus, Pencil, Trash2 } from 'lucide-react'

const defaultForm = { name: '', icon: '🚗', capacity: 4, baseFare: 50, perKm: 15, perMin: 2, minFare: 70 }

export default function VehicleTypesPage() {
  const [types, setTypes] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editItem, setEditItem] = useState<any>(null)
  const [form, setForm] = useState(defaultForm)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchTypes = () => {
    fetch('/api/vehicles/types')
      .then(r => r.json())
      .then(d => { setTypes(d.types || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchTypes() }, [])

  const openAdd = () => { setForm(defaultForm); setEditItem(null); setShowModal(true) }
  const openEdit = (t: any) => {
    setForm({ name: t.name, icon: t.icon, capacity: t.capacity, baseFare: t.baseFare, perKm: t.perKm, perMin: t.perMin, minFare: t.minFare })
    setEditItem(t)
    setShowModal(true)
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (editItem) {
      const res = await fetch(`/api/vehicles/types/${editItem._id}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchTypes(); setToast({ msg: 'Vehicle type updated', type: 'success' }) }
    } else {
      const res = await fetch('/api/vehicles/types', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchTypes(); setToast({ msg: 'Vehicle type added', type: 'success' }) }
    }
    setShowModal(false)
  }

  const handleDelete = async (id: string) => {
    const res = await fetch(`/api/vehicles/types/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchTypes(); setToast({ msg: 'Vehicle type deleted', type: 'error' }) }
  }

  if (loading) return (
    <div><Header title="Vehicle Types" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="Vehicle Types" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Vehicle Types"
          subtitle="Configure vehicle categories and pricing"
          action={
            <button type="button" onClick={openAdd}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Type
            </button>
          }
        />

        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          {types.map(t => (
            <div key={t._id} className="bg-white rounded-xl border border-gray-100 shadow-sm p-5 hover:border-blue-200 transition-colors">
              <div className="flex items-start justify-between mb-3">
                <span className="text-4xl">{t.icon}</span>
                <div className="flex gap-1">
                  <button type="button" title="Edit vehicle type" onClick={() => openEdit(t)} className="p-1.5 hover:bg-blue-50 rounded-lg text-blue-600">
                    <Pencil className="w-4 h-4" />
                  </button>
                  <button type="button" title="Delete vehicle type" onClick={() => handleDelete(t._id)} className="p-1.5 hover:bg-red-50 rounded-lg text-red-500">
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
              <h3 className="font-bold text-gray-900 text-lg">{t.name}</h3>
              <p className="text-sm text-gray-500 mb-4">{t.capacity} seats</p>
              <div className="space-y-1.5 text-sm">
                <div className="flex justify-between text-gray-600"><span>Base Fare</span><span className="font-medium text-gray-800">₹{t.baseFare}</span></div>
                <div className="flex justify-between text-gray-600"><span>Per KM</span><span className="font-medium text-gray-800">₹{t.perKm}</span></div>
                <div className="flex justify-between text-gray-600"><span>Per Min</span><span className="font-medium text-gray-800">₹{t.perMin}</span></div>
                <div className="flex justify-between text-gray-600"><span>Min Fare</span><span className="font-medium text-gray-800">₹{t.minFare}</span></div>
              </div>
            </div>
          ))}
          {types.length === 0 && (
            <div className="col-span-4 text-center text-gray-400 py-12">No vehicle types yet</div>
          )}
        </div>
      </div>

      {showModal && (
        <Modal title={editItem ? 'Edit Vehicle Type' : 'Add Vehicle Type'} onClose={() => setShowModal(false)}>
          <form onSubmit={handleSave} className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div className="col-span-2">
                <label htmlFor="vtName" className="block text-sm font-medium text-gray-700 mb-1">Type Name *</label>
                <input id="vtName" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtIcon" className="block text-sm font-medium text-gray-700 mb-1">Icon (emoji)</label>
                <input id="vtIcon" value={form.icon} onChange={e => setForm({ ...form, icon: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtCapacity" className="block text-sm font-medium text-gray-700 mb-1">Capacity (seats)</label>
                <input id="vtCapacity" type="number" value={form.capacity} onChange={e => setForm({ ...form, capacity: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtBaseFare" className="block text-sm font-medium text-gray-700 mb-1">Base Fare (₹)</label>
                <input id="vtBaseFare" type="number" value={form.baseFare} onChange={e => setForm({ ...form, baseFare: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtPerKm" className="block text-sm font-medium text-gray-700 mb-1">Per KM (₹)</label>
                <input id="vtPerKm" type="number" step="0.1" value={form.perKm} onChange={e => setForm({ ...form, perKm: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtPerMin" className="block text-sm font-medium text-gray-700 mb-1">Per Min (₹)</label>
                <input id="vtPerMin" type="number" step="0.1" value={form.perMin} onChange={e => setForm({ ...form, perMin: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="vtMinFare" className="block text-sm font-medium text-gray-700 mb-1">Min Fare (₹)</label>
                <input id="vtMinFare" type="number" value={form.minFare} onChange={e => setForm({ ...form, minFare: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Save</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
