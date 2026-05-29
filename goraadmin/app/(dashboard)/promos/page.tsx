'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Copy, Trash2 } from 'lucide-react'

const defaultForm = { code: '', type: 'percent' as 'percent' | 'flat', value: 10, minOrderAmount: 100, maxUses: 100, expiryDate: '' }

export default function PromosPage() {
  const [promos, setPromos] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState(defaultForm)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' | 'info' } | null>(null)

  const fetchPromos = () => {
    fetch('/api/promos')
      .then(r => r.json())
      .then(d => { setPromos(d.promos || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchPromos() }, [])

  const toggleStatus = async (id: string, current: boolean) => {
    const res = await fetch(`/api/promos/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ isActive: !current }),
    })
    if (res.ok) setPromos(prev => prev.map(p => p._id === id ? { ...p, isActive: !current } : p))
  }

  const deletePromo = async (id: string) => {
    const res = await fetch(`/api/promos/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchPromos(); setToast({ msg: 'Promo code deleted', type: 'error' }) }
  }

  const copyCode = (code: string) => {
    navigator.clipboard?.writeText(code).catch(() => {})
    setToast({ msg: `Code "${code}" copied!`, type: 'info' })
  }

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.code || !form.expiryDate) {
      setToast({ msg: 'Please fill all required fields', type: 'error' })
      return
    }
    const res = await fetch('/api/promos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, code: form.code.toUpperCase(), isActive: true, usedCount: 0 }),
    })
    if (res.ok) {
      fetchPromos()
      setShowModal(false)
      setForm(defaultForm)
      setToast({ msg: 'Promo code created!', type: 'success' })
    } else {
      const d = await res.json()
      setToast({ msg: d.error || 'Failed to create promo', type: 'error' })
    }
  }

  return (
    <div>
      <Header title="Promo Codes" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Promo Codes"
          subtitle="Manage discount codes and offers"
          action={
            <button type="button" onClick={() => setShowModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Promo Code
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
                  {['Code', 'Discount', 'Min Order', 'Max Uses', 'Used', 'Expiry', 'Status', 'Actions'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {promos.map(p => (
                  <tr key={p._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <span className="font-mono font-bold text-gray-900 bg-gray-100 px-2 py-0.5 rounded">{p.code}</span>
                        <button type="button" title="Copy code" onClick={() => copyCode(p.code)} className="text-gray-400 hover:text-blue-600">
                          <Copy className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                    <td className="px-4 py-3 font-semibold text-gray-800">
                      {p.type === 'percent' ? `${p.value}%` : `₹${p.value}`}
                    </td>
                    <td className="px-4 py-3 text-gray-600">₹{p.minOrderAmount || 0}</td>
                    <td className="px-4 py-3 text-gray-600">{p.maxUses || '∞'}</td>
                    <td className="px-4 py-3 text-gray-600">{p.usedCount || 0}</td>
                    <td className="px-4 py-3 text-gray-500">{p.expiryDate ? new Date(p.expiryDate).toLocaleDateString() : '—'}</td>
                    <td className="px-4 py-3">
                      <button type="button" title={p.isActive ? 'Deactivate' : 'Activate'} onClick={() => toggleStatus(p._id, p.isActive)}
                        className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${p.isActive ? 'bg-primary' : 'bg-gray-200'}`}>
                        <span className={`inline-block h-3 w-3 transform rounded-full bg-white shadow-sm transition-transform ${p.isActive ? 'translate-x-5' : 'translate-x-1'}`} />
                      </button>
                    </td>
                    <td className="px-4 py-3">
                      <button type="button" title="Delete promo" onClick={() => deletePromo(p._id)}
                        className="p-1.5 hover:bg-red-50 rounded-lg text-red-400">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
                {promos.length === 0 && (
                  <tr><td colSpan={8} className="text-center text-gray-400 py-12">No promo codes yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showModal && (
        <Modal title="Add Promo Code" onClose={() => setShowModal(false)}>
          <form onSubmit={handleAdd} className="space-y-4">
            <div>
              <label htmlFor="promoCode" className="block text-sm font-medium text-gray-700 mb-1">Promo Code *</label>
              <input id="promoCode" required value={form.code} onChange={e => setForm({ ...form, code: e.target.value.toUpperCase() })}
                placeholder="e.g. SUMMER30"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono uppercase" />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label htmlFor="promoType" className="block text-sm font-medium text-gray-700 mb-1">Discount Type</label>
                <select id="promoType" value={form.type} onChange={e => setForm({ ...form, type: e.target.value as 'percent' | 'flat' })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <option value="percent">Percentage (%)</option>
                  <option value="flat">Flat Amount (₹)</option>
                </select>
              </div>
              <div>
                <label htmlFor="promoValue" className="block text-sm font-medium text-gray-700 mb-1">
                  Value ({form.type === 'percent' ? '%' : '₹'}) *
                </label>
                <input id="promoValue" required type="number" value={form.value} onChange={e => setForm({ ...form, value: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="promoMin" className="block text-sm font-medium text-gray-700 mb-1">Min Order (₹)</label>
                <input id="promoMin" type="number" value={form.minOrderAmount} onChange={e => setForm({ ...form, minOrderAmount: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div>
                <label htmlFor="promoMax" className="block text-sm font-medium text-gray-700 mb-1">Max Uses</label>
                <input id="promoMax" type="number" value={form.maxUses} onChange={e => setForm({ ...form, maxUses: +e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
            </div>
            <div>
              <label htmlFor="promoExpiry" className="block text-sm font-medium text-gray-700 mb-1">Expiry Date *</label>
              <input id="promoExpiry" required type="date" value={form.expiryDate} onChange={e => setForm({ ...form, expiryDate: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-primary text-white rounded-lg py-2 text-sm font-medium hover:bg-primary-dark">Create Code</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
