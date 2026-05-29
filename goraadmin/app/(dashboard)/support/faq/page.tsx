'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, ChevronDown, ChevronRight, Pencil, Trash2 } from 'lucide-react'

export default function FAQPage() {
  const [faqs, setFaqs] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [showModal, setShowModal] = useState(false)
  const [editItem, setEditItem] = useState<any>(null)
  const [form, setForm] = useState({ question: '', answer: '', category: 'general' })
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchFAQs = () => {
    fetch('/api/support/faq')
      .then(r => r.json())
      .then(d => { setFaqs(d.faqs || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchFAQs() }, [])

  const openAdd = () => { setForm({ question: '', answer: '', category: 'general' }); setEditItem(null); setShowModal(true) }
  const openEdit = (faq: any) => {
    setForm({ question: faq.question, answer: faq.answer, category: faq.category })
    setEditItem(faq)
    setShowModal(true)
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (editItem) {
      const res = await fetch(`/api/support/faq/${editItem._id}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchFAQs(); setToast({ msg: 'FAQ updated', type: 'success' }) }
    } else {
      const res = await fetch('/api/support/faq', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchFAQs(); setToast({ msg: 'FAQ added', type: 'success' }) }
    }
    setShowModal(false)
  }

  const deleteFaq = async (id: string) => {
    const res = await fetch(`/api/support/faq/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchFAQs(); setToast({ msg: 'FAQ deleted', type: 'error' }) }
  }

  const categories = Array.from(new Set(faqs.map(f => f.category).filter(Boolean)))

  if (loading) return (
    <div><Header title="FAQ" />
      <div className="p-6 flex items-center justify-center h-64">
        <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
      </div>
    </div>
  )

  return (
    <div>
      <Header title="FAQ" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="Frequently Asked Questions"
          subtitle="Manage help content for users and drivers"
          action={
            <button type="button" onClick={openAdd}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add FAQ
            </button>
          }
        />

        {categories.length === 0 && faqs.length === 0 && (
          <div className="text-center text-gray-400 py-12">No FAQs yet</div>
        )}

        {(categories.length > 0 ? categories : ['general']).map(cat => {
          const catFaqs = faqs.filter(f => f.category === cat)
          if (catFaqs.length === 0) return null
          return (
            <div key={cat}>
              <h3 className="text-sm font-semibold text-gray-500 tracking-wide mb-3 px-1 capitalize">{cat}</h3>
              <div className="space-y-2">
                {catFaqs.map(faq => (
                  <div key={faq._id} className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
                    <button type="button"
                      onClick={() => setExpanded(expanded === faq._id ? null : faq._id)}
                      className="w-full flex items-center justify-between p-4 text-left hover:bg-gray-50">
                      <span className="font-medium text-gray-800 pr-4">{faq.question}</span>
                      <div className="flex items-center gap-2 flex-shrink-0">
                        <button type="button" title="Edit FAQ" onClick={e => { e.stopPropagation(); openEdit(faq) }}
                          className="p-1 hover:bg-gray-100 rounded text-gray-400 hover:text-blue-600">
                          <Pencil className="w-4 h-4" />
                        </button>
                        <button type="button" title="Delete FAQ" onClick={e => { e.stopPropagation(); deleteFaq(faq._id) }}
                          className="p-1 hover:bg-red-50 rounded text-gray-400 hover:text-red-500">
                          <Trash2 className="w-4 h-4" />
                        </button>
                        {expanded === faq._id ? <ChevronDown className="w-4 h-4 text-gray-400" /> : <ChevronRight className="w-4 h-4 text-gray-400" />}
                      </div>
                    </button>
                    {expanded === faq._id && (
                      <div className="px-4 pb-4">
                        <div className="h-px bg-gray-100 mb-3" />
                        <p className="text-sm text-gray-600 leading-relaxed">{faq.answer}</p>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )
        })}
      </div>

      {showModal && (
        <Modal title={editItem ? 'Edit FAQ' : 'Add FAQ'} onClose={() => setShowModal(false)}>
          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label htmlFor="faqQuestion" className="block text-sm font-medium text-gray-700 mb-1">Question *</label>
              <input id="faqQuestion" required value={form.question} onChange={e => setForm({ ...form, question: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="What is..." />
            </div>
            <div>
              <label htmlFor="faqAnswer" className="block text-sm font-medium text-gray-700 mb-1">Answer *</label>
              <textarea id="faqAnswer" required rows={4} value={form.answer} onChange={e => setForm({ ...form, answer: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
                placeholder="Type the answer here..." />
            </div>
            <div>
              <label htmlFor="faqCategory" className="block text-sm font-medium text-gray-700 mb-1">Category</label>
              <select id="faqCategory" value={form.category} onChange={e => setForm({ ...form, category: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="rider">Rider</option>
                <option value="driver">Driver</option>
                <option value="payment">Payment</option>
                <option value="general">General</option>
              </select>
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
