'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Bell, Send, Clock, ImagePlus } from 'lucide-react'

export default function NotificationsPage() {
  const [form, setForm] = useState({ title: '', message: '', target: 'all', scheduleType: 'now', scheduleTime: '', targetPhone: '', imageUrl: '' })
  const [uploading, setUploading] = useState(false)
  const uploadImage = async (f: File | undefined) => {
    if (!f) return
    setUploading(true)
    const fd = new FormData(); fd.append('file', f)
    const r = await fetch('/api/upload', { method: 'POST', body: fd })
    const d = await r.json().catch(() => ({}))
    setUploading(false)
    if (!r.ok || !d.url) { setToast({ msg: d.error || 'Upload failed', type: 'error' }); return }
    setForm(prev => ({ ...prev, imageUrl: d.url }))
  }
  const [sending, setSending] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' | 'error' } | null>(null)
  const [history, setHistory] = useState<any[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/notifications')
      .then(r => r.json())
      .then(d => { setHistory(d.notifications || []); setLoading(false) })
      .catch(() => setLoading(false))
  }, [])

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.title || !form.message) {
      setToast({ msg: 'Please fill title and message', type: 'error' })
      return
    }
    const scheduling = form.scheduleType === 'schedule'
    let scheduledAt: string | undefined
    if (scheduling) {
      // datetime-local is the admin's own local time; send it as an exact instant.
      const at = form.scheduleTime ? new Date(form.scheduleTime) : null
      if (!at || Number.isNaN(at.getTime())) { setToast({ msg: 'Choose the date and time to send it', type: 'error' }); return }
      if (at.getTime() < Date.now() + 60_000) { setToast({ msg: 'Schedule it at least 1 minute from now', type: 'error' }); return }
      scheduledAt = at.toISOString()
    }
    setSending(true)
    const res = await fetch('/api/notifications', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: form.title, message: form.message, target: form.target, targetPhone: form.targetPhone, imageUrl: form.imageUrl, scheduledAt }),
    })
    setSending(false)
    const d = await res.json().catch(() => ({}))
    if (res.ok) {
      setHistory(prev => [d.notification, ...prev])
      setForm({ title: '', message: '', target: 'all', scheduleType: 'now', scheduleTime: '', targetPhone: '', imageUrl: '' })
      setToast({
        msg: d.scheduled ? `Scheduled for ${new Date(d.notification.scheduledAt).toLocaleString()}` : 'Notification sent successfully!',
        type: 'success',
      })
    } else {
      setToast({ msg: d.error || 'Failed to send notification', type: 'error' })
    }
  }

  const cancelScheduled = async (id: string) => {
    const res = await fetch(`/api/notifications?id=${id}`, { method: 'DELETE' })
    const d = await res.json().catch(() => ({}))
    if (!res.ok) { setToast({ msg: d.error || 'Could not cancel', type: 'error' }); return }
    setHistory(prev => prev.map(n => (n._id === id ? { ...n, status: 'cancelled' } : n)))
    setToast({ msg: 'Scheduled notification cancelled', type: 'success' })
  }

  // Earliest value the picker allows: one minute from now, in local time.
  const minLocal = () => {
    const d = new Date(Date.now() + 2 * 60_000)
    const p = (x: number) => String(x).padStart(2, '0')
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
  }

  return (
    <div>
      <Header title="Notifications" />
      <div className="p-6 space-y-6">
        <PageHeader title="Push Notifications" subtitle="Send targeted push notifications to users and drivers" />

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
          <h3 className="font-semibold text-gray-800 mb-5 flex items-center gap-2">
            <Bell className="w-5 h-5 text-blue-600" /> Send Notification
          </h3>
          <form onSubmit={handleSend} className="space-y-5">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
              <div className="sm:col-span-2">
                <label htmlFor="notifTitle" className="block text-sm font-medium text-gray-700 mb-1">Title *</label>
                <input id="notifTitle" required value={form.title} onChange={e => setForm({ ...form, title: e.target.value })}
                  placeholder="Notification title"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </div>
              <div className="sm:col-span-2">
                <label htmlFor="notifMessage" className="block text-sm font-medium text-gray-700 mb-1">Message *</label>
                <textarea id="notifMessage" required rows={3} value={form.message} onChange={e => setForm({ ...form, message: e.target.value })}
                  placeholder="Notification body text"
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none" />
              </div>
              <div>
                <label htmlFor="notifTarget" className="block text-sm font-medium text-gray-700 mb-1">Target Audience</label>
                <select id="notifTarget" value={form.target} onChange={e => setForm({ ...form, target: e.target.value })}
                  className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-500">
                  <option value="all">All Users</option>
                  <option value="riders">All Riders</option>
                  <option value="drivers">All Drivers</option>
                  <option value="specific">Specific User</option>
                </select>
                {form.target === 'specific' && (
                  <input aria-label="Phone number" value={form.targetPhone} onChange={e => setForm({ ...form, targetPhone: e.target.value })}
                    placeholder="Rider or driver phone number"
                    className="mt-2 w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                )}
              </div>
              <div className="sm:col-span-2">
                <p className="block text-sm font-medium text-gray-700 mb-1">Image (optional)</p>
                <div className="flex flex-wrap items-start gap-3">
                  {form.imageUrl ? (
                    <div className="relative">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={form.imageUrl} alt="Notification" className="h-28 w-48 object-cover rounded-lg border" />
                      <button type="button" onClick={() => setForm({ ...form, imageUrl: '' })}
                        className="absolute -top-2 -right-2 w-6 h-6 rounded-full bg-red-600 text-white text-xs">✕</button>
                    </div>
                  ) : (
                    <label className="h-28 w-48 border-2 border-dashed border-gray-300 rounded-lg flex flex-col items-center justify-center text-xs text-gray-500 cursor-pointer hover:border-primary">
                      <ImagePlus className="w-6 h-6 mb-1" />
                      {uploading ? 'Uploading…' : 'Upload image'}
                      <input type="file" accept="image/*" className="hidden" onChange={e => uploadImage(e.target.files?.[0])} />
                    </label>
                  )}
                  <div className="flex-1 min-w-[220px]">
                    <input value={form.imageUrl} onChange={e => setForm({ ...form, imageUrl: e.target.value })}
                      placeholder="…or paste an image link (https://)"
                      className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                    <p className="text-xs text-gray-500 mt-1">Shown in the app&apos;s notification list and, on phones with push enabled, as the big picture of the notification.</p>
                  </div>
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Send Type</label>
                <div className="flex gap-4">
                  {[{ val: 'now', label: 'Send Now', icon: Send }, { val: 'schedule', label: 'Schedule', icon: Clock }].map(opt => (
                    <label key={opt.val} className="flex items-center gap-2 cursor-pointer">
                      <input type="radio" name="scheduleType" value={opt.val}
                        checked={form.scheduleType === opt.val}
                        onChange={e => setForm({ ...form, scheduleType: e.target.value })}
                        className="text-blue-600" />
                      <opt.icon className="w-4 h-4 text-gray-500" />
                      <span className="text-sm text-gray-700">{opt.label}</span>
                    </label>
                  ))}
                </div>
                {form.scheduleType === 'schedule' && (
                  <div className="mt-3">
                    <label htmlFor="notifWhen" className="block text-xs font-medium text-gray-600 mb-1">Send on</label>
                    <input id="notifWhen" type="datetime-local" min={minLocal()} value={form.scheduleTime}
                      onChange={e => setForm({ ...form, scheduleTime: e.target.value })}
                      className="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
                    <p className="text-xs text-gray-500 mt-1">It goes out at this time (up to 60 days ahead). Until then riders and drivers don&apos;t see it, and you can cancel it below.</p>
                  </div>
                )}
              </div>
            </div>
            <button type="submit" disabled={sending}
              className="flex items-center gap-2 px-6 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
              <Send className="w-4 h-4" />
              {sending ? (form.scheduleType === 'now' ? 'Sending...' : 'Scheduling...') : form.scheduleType === 'now' ? 'Send Now' : 'Schedule'}
            </button>
          </form>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
          <h3 className="font-semibold text-gray-800 mb-4">Notifications</h3>
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Title', 'Target', 'Status', 'When', 'Delivered'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {history.map((n: any) => (
                    <tr key={n._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-medium text-gray-800">
                        <span className="flex items-center gap-2">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          {n.imageUrl && <img src={n.imageUrl} alt="" className="w-10 h-10 rounded object-cover border" />}
                          <span>{n.title}<span className="block text-xs font-normal text-gray-500 truncate max-w-xs">{n.message}</span></span>
                        </span>
                      </td>
                      <td className="px-4 py-3 text-gray-600 capitalize">{n.target}</td>
                      <td className="px-4 py-3">
                        {n.status === 'scheduled' ? (
                          <span className="inline-flex items-center gap-2">
                            <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-amber-100 text-amber-800">Scheduled</span>
                            <button type="button" onClick={() => cancelScheduled(n._id)} className="text-xs text-red-600 hover:underline">Cancel</button>
                          </span>
                        ) : n.status === 'cancelled' ? (
                          <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-gray-100 text-gray-600">Cancelled</span>
                        ) : (
                          <span className="px-2 py-0.5 rounded-full text-xs font-semibold bg-green-100 text-green-800">Sent</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-gray-500 text-xs">
                        {n.status === 'scheduled' || n.status === 'cancelled'
                          ? (n.scheduledAt ? `For ${new Date(n.scheduledAt).toLocaleString()}` : '—')
                          : (n.sentAt ? new Date(n.sentAt).toLocaleString() : '—')}
                      </td>
                      <td className="px-4 py-3">
                        {n.status === 'scheduled' || n.status === 'cancelled' ? <span className="text-gray-400">—</span> : (
                          <span className="flex items-center gap-1 text-green-700 font-medium">
                            <div className="w-1.5 h-1.5 rounded-full bg-green-500" />
                            {(n.deliveredCount || 0).toLocaleString()}
                          </span>
                        )}
                      </td>
                    </tr>
                  ))}
                  {history.length === 0 && (
                    <tr><td colSpan={5}className="text-center text-gray-400 py-8">No notifications sent yet</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
