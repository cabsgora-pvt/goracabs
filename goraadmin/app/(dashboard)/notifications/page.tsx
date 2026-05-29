'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Toast } from '@/components/ui/toast'
import { Bell, Send, Clock } from 'lucide-react'

export default function NotificationsPage() {
  const [form, setForm] = useState({ title: '', message: '', target: 'all', scheduleType: 'now', scheduleTime: '' })
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
    setSending(true)
    const res = await fetch('/api/notifications', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: form.title, message: form.message, target: form.target }),
    })
    setSending(false)
    if (res.ok) {
      const d = await res.json()
      setHistory(prev => [d.notification, ...prev])
      setForm({ title: '', message: '', target: 'all', scheduleType: 'now', scheduleTime: '' })
      setToast({ msg: form.scheduleType === 'now' ? 'Notification sent successfully!' : 'Notification scheduled!', type: 'success' })
    } else {
      setToast({ msg: 'Failed to send notification', type: 'error' })
    }
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
              </div>
            </div>
            <button type="submit" disabled={sending}
              className="flex items-center gap-2 px-6 py-2.5 bg-primary text-white rounded-lg text-sm font-semibold hover:bg-primary-dark disabled:opacity-60">
              <Send className="w-4 h-4" />
              {sending ? 'Sending...' : form.scheduleType === 'now' ? 'Send Now' : 'Schedule'}
            </button>
          </form>
        </div>

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm p-6">
          <h3 className="font-semibold text-gray-800 mb-4">Sent Notifications</h3>
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-100">
                    {['Title', 'Target', 'Sent At', 'Delivered'].map(h => (
                      <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-50">
                  {history.map((n: any) => (
                    <tr key={n._id} className="hover:bg-gray-50">
                      <td className="px-4 py-3 font-medium text-gray-800">{n.title}</td>
                      <td className="px-4 py-3 text-gray-600 capitalize">{n.target}</td>
                      <td className="px-4 py-3 text-gray-500 text-xs">{n.sentAt ? new Date(n.sentAt).toLocaleString() : '—'}</td>
                      <td className="px-4 py-3">
                        <span className="flex items-center gap-1 text-green-700 font-medium">
                          <div className="w-1.5 h-1.5 rounded-full bg-green-500" />
                          {(n.deliveredCount || 0).toLocaleString()}
                        </span>
                      </td>
                    </tr>
                  ))}
                  {history.length === 0 && (
                    <tr><td colSpan={4} className="text-center text-gray-400 py-8">No notifications sent yet</td></tr>
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
