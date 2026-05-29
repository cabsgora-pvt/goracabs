'use client'
import { useState, useEffect } from 'react'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { StatsCard } from '@/components/ui/stats-card'
import { Badge } from '@/components/ui/badge'
import { Modal } from '@/components/ui/modal'
import { Toast } from '@/components/ui/toast'
import { MessageSquare, Clock, CheckCircle, Eye, Send } from 'lucide-react'

export default function TicketsPage() {
  const [tickets, setTickets] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [viewTicket, setViewTicket] = useState<any>(null)
  const [reply, setReply] = useState('')
  const [sending, setSending] = useState(false)
  const [toast, setToast] = useState<{ msg: string; type: 'success' } | null>(null)

  const fetchTickets = () => {
    fetch('/api/support/tickets?limit=100')
      .then(r => r.json())
      .then(d => { setTickets(d.tickets || []); setLoading(false) })
      .catch(() => setLoading(false))
  }

  useEffect(() => { fetchTickets() }, [])

  const sendReply = async () => {
    if (!reply.trim() || !viewTicket) return
    setSending(true)
    const res = await fetch(`/api/support/tickets/${viewTicket._id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: reply, sender: 'admin', status: 'resolved' }),
    })
    setSending(false)
    if (res.ok) {
      const updated = await res.json()
      setTickets(prev => prev.map(t => t._id === viewTicket._id ? updated : t))
      setViewTicket(updated)
      setReply('')
      setToast({ msg: 'Reply sent and ticket resolved', type: 'success' })
    }
  }

  return (
    <div>
      <Header title="Support Tickets" />
      <div className="p-6 space-y-6">
        <PageHeader title="Support Tickets" subtitle="Handle customer and driver support requests" />

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <StatsCard icon={MessageSquare} label="Open" value={tickets.filter(t => t.status === 'open').length} iconColor="text-red-600" iconBg="bg-red-50" />
          <StatsCard icon={Clock} label="In Progress" value={tickets.filter(t => t.status === 'in_progress').length} iconColor="text-yellow-600" iconBg="bg-yellow-50" />
          <StatsCard icon={CheckCircle} label="Resolved" value={tickets.filter(t => t.status === 'resolved').length} iconColor="text-green-600" iconBg="bg-green-50" />
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
                  {['User', 'Subject', 'Category', 'Priority', 'Status', 'Date', 'Actions'].map(h => (
                    <th key={h} className="text-left text-xs font-semibold text-gray-500 uppercase px-4 py-3">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {tickets.map(t => (
                  <tr key={t._id} className="hover:bg-gray-50">
                    <td className="px-4 py-3 font-medium text-gray-800">{t.userName || '—'}</td>
                    <td className="px-4 py-3 text-gray-700">{t.subject}</td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{t.category}</td>
                    <td className="px-4 py-3"><Badge status={t.priority} /></td>
                    <td className="px-4 py-3"><Badge status={t.status} /></td>
                    <td className="px-4 py-3 text-gray-500 text-xs">{t.createdAt ? new Date(t.createdAt).toLocaleDateString() : '—'}</td>
                    <td className="px-4 py-3">
                      <button type="button" onClick={() => setViewTicket(t)}
                        className="flex items-center gap-1 px-3 py-1 bg-blue-50 text-blue-600 rounded-lg text-xs hover:bg-blue-100">
                        <Eye className="w-3.5 h-3.5" /> View
                      </button>
                    </td>
                  </tr>
                ))}
                {tickets.length === 0 && (
                  <tr><td colSpan={7} className="text-center text-gray-400 py-12">No tickets yet</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {viewTicket && (
        <Modal title={`${viewTicket.subject}`} onClose={() => setViewTicket(null)} size="lg">
          <div className="space-y-4">
            <div className="flex gap-3 flex-wrap">
              <Badge status={viewTicket.status} />
              <Badge status={viewTicket.priority} />
              {viewTicket.category && (
                <span className="text-xs text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">{viewTicket.category}</span>
              )}
            </div>
            <div className="space-y-3 max-h-60 overflow-y-auto">
              {(viewTicket.messages || []).map((msg: any, i: number) => (
                <div key={msg._id || i} className={`flex ${msg.sender === 'admin' ? 'justify-end' : 'justify-start'}`}>
                  <div className={`max-w-xs rounded-xl p-3 ${msg.sender === 'admin' ? 'bg-blue-50 text-blue-900' : 'bg-gray-100 text-gray-800'}`}>
                    <p className="text-xs font-semibold mb-1 capitalize">{msg.sender}</p>
                    <p className="text-sm">{msg.message}</p>
                    <p className="text-xs text-gray-400 mt-1">{msg.sentAt ? new Date(msg.sentAt).toLocaleString() : ''}</p>
                  </div>
                </div>
              ))}
              {(!viewTicket.messages || viewTicket.messages.length === 0) && (
                <p className="text-gray-400 text-sm text-center py-4">No messages yet</p>
              )}
            </div>
            {viewTicket.status !== 'resolved' && viewTicket.status !== 'closed' && (
              <div className="flex gap-3 pt-2 border-t border-gray-100">
                <input
                  value={reply}
                  onChange={e => setReply(e.target.value)}
                  placeholder="Type your reply..."
                  className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  onKeyDown={e => e.key === 'Enter' && sendReply()}
                />
                <button type="button" onClick={sendReply} disabled={sending}
                  className="flex items-center gap-2 px-4 py-2 bg-primary text-white rounded-lg text-sm font-medium hover:bg-primary-dark disabled:opacity-60">
                  <Send className="w-4 h-4" /> Reply
                </button>
              </div>
            )}
          </div>
        </Modal>
      )}

      {toast && <Toast message={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  )
}
