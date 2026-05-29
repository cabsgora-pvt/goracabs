'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { Plus, Trash2, Pencil } from 'lucide-react'

const defaultForm = { title: '', targetScreen: 'home', imageUrl: '', linkUrl: '', isActive: true, color: '#1565C0' }

export default function BannersPage() {
  const [banners, setBanners] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [showModal, setShowModal] = useState(false)
  const [editItem, setEditItem] = useState<any>(null)
  const [form, setForm] = useState(defaultForm)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)

  const fetchBanners = () => {
    fetch('/api/banners')
      .then(r => r.json())
      .then(d => { setBanners(d.banners || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchBanners() }, [])

  const openAdd = () => { setForm(defaultForm); setEditItem(null); setShowModal(true) }
  const openEdit = (b: any) => {
    setForm({ title: b.title, targetScreen: b.targetScreen || 'home', imageUrl: b.imageUrl || '', linkUrl: b.linkUrl || '', isActive: b.isActive, color: b.color || '#1565C0' })
    setEditItem(b)
    setShowModal(true)
  }

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (editItem) {
      const res = await fetch(`/api/banners/${editItem._id}`, {
        method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchBanners(); setToast({ msg: 'Banner updated', type: 'success' }) }
    } else {
      const res = await fetch('/api/banners', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(form),
      })
      if (res.ok) { fetchBanners(); setToast({ msg: 'Banner added', type: 'success' }) }
    }
    setShowModal(false)
  }

  const toggleBanner = async (id: string, current: boolean) => {
    const res = await fetch(`/api/banners/${id}`, {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ isActive: !current }),
    })
    if (res.ok) setBanners(prev => prev.map(b => b._id === id ? { ...b, isActive: !current } : b))
  }

  const deleteBanner = async (id: string) => {
    const res = await fetch(`/api/banners/${id}`, { method: 'DELETE' })
    if (res.ok) { fetchBanners(); setToast({ msg: 'Banner deleted', type: 'error' }) }
  }

  return (
    <div>
      <Header title="Banners" />
      <div className="p-6 space-y-6">
        <PageHeader
          title="App Banners"
          subtitle="Manage promotional banners shown in the app"
          action={
            <button type="button" onClick={openAdd}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark">
              <Plus className="w-4 h-4" /> Add Banner
            </button>
          }
        />

        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
            {banners.map(b => (
              <div key={b._id} className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
                <div className="h-32 flex items-center justify-center relative" style={{ background: b.color || '#1565C0' }}>
                  <p className="text-white font-bold text-lg">{b.title}</p>
                  <div className="absolute top-2 right-2 flex gap-1">
                    <button type="button" title="Edit banner" onClick={() => openEdit(b)}
                      className="w-7 h-7 bg-white/20 hover:bg-white/40 rounded-lg flex items-center justify-center text-white">
                      <Pencil className="w-3.5 h-3.5" />
                    </button>
                    <button type="button" title="Delete banner" onClick={() => deleteBanner(b._id)}
                      className="w-7 h-7 bg-white/20 hover:bg-red-500 rounded-lg flex items-center justify-center text-white">
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
                <div className="p-4">
                  <div className="flex items-center justify-between mb-2">
                    <div>
                      <p className="font-semibold text-gray-900">{b.title}</p>
                      <p className="text-xs text-gray-500 mt-0.5 capitalize">Screen: {b.targetScreen}</p>
                    </div>
                    <button type="button" title={b.isActive ? 'Deactivate' : 'Activate'}
                      onClick={() => toggleBanner(b._id, b.isActive)}
                      className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${b.isActive ? 'bg-primary' : 'bg-gray-200'}`}>
                      <span className={`inline-block h-3 w-3 transform rounded-full bg-white shadow-sm transition-transform ${b.isActive ? 'translate-x-5' : 'translate-x-1'}`} />
                    </button>
                  </div>
                  {b.linkUrl && <p className="text-xs text-blue-600 truncate">{b.linkUrl}</p>}
                </div>
              </div>
            ))}
            {banners.length === 0 && (
              <div className="col-span-3 text-center text-gray-400 py-12">No banners yet</div>
            )}
          </div>
        )}
      </div>

      {showModal && (
        <Modal title={editItem ? 'Edit Banner' : 'Add Banner'} onClose={() => setShowModal(false)}>
          <form onSubmit={handleSave} className="space-y-4">
            <div>
              <label htmlFor="bannerTitle" className="block text-sm font-medium text-gray-700 mb-1">Banner Title *</label>
              <input id="bannerTitle" required value={form.title} onChange={e => setForm({ ...form, title: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="bannerScreen" className="block text-sm font-medium text-gray-700 mb-1">Target Screen</label>
              <select id="bannerScreen" value={form.targetScreen} onChange={e => setForm({ ...form, targetScreen: e.target.value })}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                <option value="home">Home</option>
                <option value="promo">Promo</option>
                <option value="splash">Splash</option>
              </select>
            </div>
            <div>
              <label htmlFor="bannerImage" className="block text-sm font-medium text-gray-700 mb-1">Image URL</label>
              <input id="bannerImage" type="url" value={form.imageUrl} onChange={e => setForm({ ...form, imageUrl: e.target.value })}
                placeholder="https://..." className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="bannerLink" className="block text-sm font-medium text-gray-700 mb-1">Link / Deep Link</label>
              <input id="bannerLink" value={form.linkUrl} onChange={e => setForm({ ...form, linkUrl: e.target.value })}
                placeholder="/promo/code" className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            </div>
            <div>
              <label htmlFor="bannerColor" className="block text-sm font-medium text-gray-700 mb-1">Background Color</label>
              <div className="flex gap-3 items-center">
                <input id="bannerColor" type="color" value={form.color} onChange={e => setForm({ ...form, color: e.target.value })}
                  className="h-10 w-16 border border-gray-300 rounded-lg cursor-pointer" />
                <span className="text-sm text-gray-600">{form.color}</span>
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
