'use client'
import { useState, useEffect, useRef } from 'react'
import Link from 'next/link'
import { Header } from '@/components/header'
import { PageHeader } from '@/components/ui/page-header'
import { Send, MessageSquare, ExternalLink } from 'lucide-react'

interface ChatListItem {
  _id: string
  driverId: string
  driverName: string
  driverPhone: string
  zoneName: string
  lastMessage: string
  lastSender: 'driver' | 'admin'
  lastMessageAt: string
  adminUnread: number
}

interface ChatMessage {
  sender: 'driver' | 'admin'
  message: string
  sentAt: string
}

interface ChatDetail {
  _id: string
  driverId: string
  driverName: string
  driverPhone: string
  zoneName: string
  messages: ChatMessage[]
}

function shortTime(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ''
  const now = Date.now()
  const diff = now - d.getTime()
  const min = Math.floor(diff / 60000)
  if (min < 1) return 'now'
  if (min < 60) return `${min}m`
  const hr = Math.floor(min / 60)
  if (hr < 24) return `${hr}h`
  const days = Math.floor(hr / 24)
  if (days < 7) return `${days}d`
  return d.toLocaleDateString()
}

function msgTime(iso: string): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (isNaN(d.getTime())) return ''
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export default function SupportChatsPage() {
  const [chats, setChats] = useState<ChatListItem[]>([])
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [detail, setDetail] = useState<ChatDetail | null>(null)
  const [input, setInput] = useState('')
  const [sending, setSending] = useState(false)
  const [loadingList, setLoadingList] = useState(true)

  const messagesEndRef = useRef<HTMLDivElement | null>(null)

  const fetchChats = () => {
    fetch('/api/support/chats')
      .then(r => r.json())
      .then(d => { setChats(d.chats || []); setLoadingList(false) })
      .catch(() => setLoadingList(false))
  }

  const fetchDetail = (id: string) => {
    fetch(`/api/support/chats/${id}`)
      .then(r => r.json())
      .then(d => { if (d && d._id) setDetail(d) })
      .catch(() => {})
  }

  // Poll the chats list on mount and every 8s
  useEffect(() => {
    fetchChats()
    const t = setInterval(fetchChats, 8000)
    return () => clearInterval(t)
  }, [])

  // Fetch + poll the selected chat every 5s
  useEffect(() => {
    if (!selectedId) { setDetail(null); return }
    setDetail(null)
    fetchDetail(selectedId)
    const t = setInterval(() => fetchDetail(selectedId), 5000)
    return () => clearInterval(t)
  }, [selectedId])

  // Auto-scroll to newest message
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [detail?.messages?.length])

  const handleSelect = (id: string) => {
    setSelectedId(id)
    // Optimistically clear the unread badge for this chat
    setChats(prev => prev.map(c => c._id === id ? { ...c, adminUnread: 0 } : c))
  }

  const handleSend = async () => {
    const text = input.trim()
    if (!text || !selectedId || sending) return
    setSending(true)
    try {
      const res = await fetch(`/api/support/chats/${selectedId}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok && data.success) {
        setInput('')
        if (Array.isArray(data.messages)) {
          setDetail(prev => prev ? { ...prev, messages: data.messages } : prev)
        } else {
          fetchDetail(selectedId)
        }
        fetchChats()
      }
    } catch {
      /* ignore, poll will recover */
    } finally {
      setSending(false)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  return (
    <div>
      <Header title="Support Chats" />
      <div className="p-6 space-y-6">
        <PageHeader title="Driver Support Chats" subtitle="Two-way conversations between admin and drivers" />

        <div className="bg-white rounded-xl border border-gray-100 shadow-sm overflow-hidden">
          <div className="flex h-[calc(100vh-16rem)] min-h-[480px]">
            {/* Left column: chat list */}
            <div className="w-[320px] flex-shrink-0 border-r border-gray-100 flex flex-col">
              <div className="px-4 py-3 border-b border-gray-100">
                <h3 className="text-sm font-semibold text-gray-700">Conversations</h3>
              </div>
              <div className="flex-1 overflow-y-auto">
                {loadingList ? (
                  <div className="flex items-center justify-center py-12">
                    <div className="w-6 h-6 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin" />
                  </div>
                ) : chats.length === 0 ? (
                  <div className="text-center text-gray-400 text-sm py-12">No conversations</div>
                ) : (
                  <ul className="divide-y divide-gray-50">
                    {chats.map(c => {
                      const active = c._id === selectedId
                      return (
                        <li key={c._id}>
                          <button
                            type="button"
                            onClick={() => handleSelect(c._id)}
                            className={`w-full text-left px-4 py-3 hover:bg-gray-50 transition-colors ${active ? 'bg-blue-50' : ''}`}
                          >
                            <div className="flex items-center justify-between gap-2">
                              <span className="font-semibold text-gray-800 truncate">{c.driverName || 'Unknown driver'}</span>
                              <span className="text-xs text-gray-400 flex-shrink-0">{shortTime(c.lastMessageAt)}</span>
                            </div>
                            {c.zoneName && (
                              <div className="text-xs text-gray-400 mt-0.5 truncate">{c.zoneName}</div>
                            )}
                            <div className="flex items-center justify-between gap-2 mt-1">
                              <span className="text-sm text-gray-500 truncate">
                                {c.lastSender === 'admin' ? 'You: ' : ''}{c.lastMessage || '—'}
                              </span>
                              {c.adminUnread > 0 && (
                                <span className="flex-shrink-0 min-w-[20px] h-5 px-1.5 flex items-center justify-center rounded-full bg-primary text-white text-xs font-semibold">
                                  {c.adminUnread}
                                </span>
                              )}
                            </div>
                          </button>
                        </li>
                      )
                    })}
                  </ul>
                )}
              </div>
            </div>

            {/* Right column: chat panel */}
            <div className="flex-1 flex flex-col min-w-0">
              {!detail ? (
                <div className="flex-1 flex flex-col items-center justify-center text-gray-400">
                  <MessageSquare className="w-10 h-10 mb-3" />
                  <p className="text-sm">Select a conversation</p>
                </div>
              ) : (
                <>
                  {/* Chat header */}
                  <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between gap-4">
                    <div className="min-w-0">
                      <div className="font-semibold text-gray-800 truncate">{detail.driverName || 'Unknown driver'}</div>
                      <div className="text-xs text-gray-500 truncate">
                        {[detail.zoneName, detail.driverPhone].filter(Boolean).join(' • ')}
                      </div>
                    </div>
                    <Link
                      href={`/drivers/${detail.driverId}`}
                      className="flex items-center gap-1.5 flex-shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium text-primary border border-gray-200 hover:bg-gray-50"
                    >
                      <ExternalLink className="w-3.5 h-3.5" /> View details
                    </Link>
                  </div>

                  {/* Messages */}
                  <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3 bg-gray-50">
                    {detail.messages.length === 0 ? (
                      <div className="text-center text-gray-400 text-sm py-8">No messages yet</div>
                    ) : (
                      detail.messages.map((m, i) => {
                        const isAdmin = m.sender === 'admin'
                        return (
                          <div key={i} className={`flex ${isAdmin ? 'justify-end' : 'justify-start'}`}>
                            <div className={`max-w-[75%] rounded-2xl px-4 py-2 ${isAdmin ? 'bg-primary text-white rounded-br-sm' : 'bg-white text-gray-800 border border-gray-100 rounded-bl-sm'}`}>
                              <p className="text-sm whitespace-pre-wrap break-words">{m.message}</p>
                              <p className={`text-[10px] mt-1 ${isAdmin ? 'text-blue-100' : 'text-gray-400'}`}>{msgTime(m.sentAt)}</p>
                            </div>
                          </div>
                        )
                      })
                    )}
                    <div ref={messagesEndRef} />
                  </div>

                  {/* Input row */}
                  <div className="px-4 py-3 border-t border-gray-100 flex items-center gap-2">
                    <input
                      type="text"
                      aria-label="Message to driver"
                      title="Message to driver"
                      value={input}
                      onChange={e => setInput(e.target.value)}
                      onKeyDown={handleKeyDown}
                      placeholder="Type a message..."
                      className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                    <button
                      type="button"
                      onClick={handleSend}
                      disabled={sending || !input.trim()}
                      aria-label="Send message"
                      title="Send message"
                      className="flex items-center gap-1.5 px-4 py-2 rounded-lg text-sm font-medium bg-primary text-white hover:bg-primary-dark disabled:opacity-50"
                    >
                      <Send className="w-4 h-4" /> Send
                    </button>
                  </div>
                </>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
