'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Trash2, Phone, AlertCircle } from 'lucide-react'

export default function SOSPage() {
  const [contacts, setContacts] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [form, setForm] = useState({ name: '', phone: '', relation: '' })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchContacts = () => {
    fetch('/api/support/sos')
      .then(r => r.json())
      .then(d => { setContacts(d.contacts || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchContacts() }, [])

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    const res = await fetch('/api/support/sos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, addedBy: 'admin', isActive: true }),
    })
    if (res.ok) {
      fetchContacts()
      setShowModal(false)
      setForm({ name: '', phone: '', relation: '' })
      setToast({ msg: 'SOS contact added', type: 'success' })
    }
  }

  const deleteContact = async (id: string) => {
    const res = await fetch(`/api/support/sos/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchContacts(); setToast({ msg: 'Contact removed', type: 'error' }) }
  }

  return (
    <div>
      <Header title="SOS Contacts" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="SOS Emergency Contacts"
          subtitle="Manage emergency contacts shown to users during rides"
          action={
            <button type="button" onClick={() => setShowModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add SOS Contact
            </button>
          }
        />

        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-700">
            These contacts are displayed to users when they press the SOS button during a ride. Ensure all numbers are active and verified.
          </p>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-gray-50 border-b border-gray-100">
                  {['Name', 'Phone', 'Relation / Type', 'Added By', 'Actions'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {contacts.map(c => (
                  <tr key={c._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium text-gray-800">{c.name}</td>
                    <td className="px-4 py-3">
                      <a href={`tel:${c.phone}`} className="flex items-center gap-1.5 text-blue-600 hover:text-blue-800">
                        <Phone className="w-3.5 h-3.5" />
                        <span className="font-mono">{c.phone}</span>
                      </a>
                    </td>
                    <td className="px-4 py-3 text-gray-600">{c.relation}</td>
                    <td className="px-4 py-3">
                      <span className="text-xs px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full capitalize">{c.addedBy}</span>
                    </td>
                    <td className="px-4 py-3">
                      <button type="button" title="Remove contact" onClick={() => deleteContact(c._id)}
                        className="p-1.5 hover:bg-red-50 rounded-lg text-red-400 hover:text-red-600">
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
                {contacts.length === 0 && (
                  <tr><td colSpan={5} className="text-center text-gray-400 py-12">No SOS contacts yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showModal && (
        <Modal title="Add SOS Contact" onClose={() => setShowModal(false)} size="sm">
          <form onSubmit={handleAdd} className="space-y-4">
            <div>
              <label htmlFor="sosName" className="block text-sm font-medium text-gray-700 mb-1">Name *</label>
              <input id="sosName" required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })}
                placeholder="e.g. Local Police Station"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="sosPhone" className="block text-sm font-medium text-gray-700 mb-1">Phone Number *</label>
              <input id="sosPhone" required value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })}
                placeholder="100 or +91 XXXXX XXXXX"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="sosRelation" className="block text-sm font-medium text-gray-700 mb-1">Relation / Type *</label>
              <input id="sosRelation" required value={form.relation} onChange={e => setForm({ ...form, relation: e.target.value })}
                placeholder="e.g. Emergency, Support"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div className="flex gap-3 pt-2">
              <button type="button" onClick={() => setShowModal(false)}
                className="flex-1 border border-gray-300 text-gray-700 rounded-lg py-2 text-sm font-medium hover:bg-gray-50">Cancel</button>
              <button type="submit"
                className="flex-1 bg-red-600 text-white rounded-lg py-2 text-sm font-medium hover:bg-red-700">Add Contact</button>
            </div>
          </form>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
