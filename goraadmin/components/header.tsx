'use client'
import { useState } from 'react'
import { Bell, Search, ChevronDown, User, LogOut, Settings } from 'lucide-react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

interface HeaderProps {
  title: string
}

export function Header({ title }: HeaderProps) {
  const router = useRouter()
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const [notifOpen, setNotifOpen] = useState(false)

  return (
    <header className="h-16 bg-white border-b border-gray-100 flex items-center px-6 gap-4 sticky top-0 z-30 shadow-sm">
      {/* Title */}
      <div className="flex-1 min-w-0 ml-8 lg:ml-0">
        <h2 className="text-lg font-semibold text-gray-800 truncate">{title}</h2>
      </div>

      {/* Search */}
      <div className="hidden md:flex items-center bg-gray-50 border border-gray-200 rounded-lg px-3 py-2 gap-2 w-64">
        <Search className="w-4 h-4 text-gray-400 flex-shrink-0" />
        <input
          placeholder="Search..."
          className="bg-transparent text-sm text-gray-700 outline-none w-full placeholder-gray-400"
        />
      </div>

      {/* Notifications */}
      <div className="relative">
        <button
          onClick={() => { setNotifOpen(!notifOpen); setDropdownOpen(false) }}
          className="relative w-10 h-10 flex items-center justify-center rounded-full hover:bg-gray-100 text-gray-600"
        >
          <Bell className="w-5 h-5" />
          <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-red-500 rounded-full" />
        </button>
        {notifOpen && (
          <div className="absolute right-0 mt-2 w-80 bg-white rounded-xl shadow-xl border border-gray-100 z-50">
            <div className="px-4 py-3 border-b border-gray-100">
              <p className="font-semibold text-gray-800">Notifications</p>
            </div>
            <div className="divide-y divide-gray-50 max-h-72 overflow-y-auto">
              {[
                { text: '3 new driver approvals pending', time: '5m ago', color: 'bg-yellow-100' },
                { text: 'New support ticket: App crash on booking', time: '12m ago', color: 'bg-red-100' },
                { text: '5 withdrawal requests awaiting', time: '1h ago', color: 'bg-blue-100' },
                { text: 'Promo GORA25 has expired', time: '2h ago', color: 'bg-gray-100' },
              ].map((n, i) => (
                <div key={i} className="px-4 py-3 hover:bg-gray-50 flex items-start gap-3">
                  <div className={`w-2 h-2 rounded-full mt-2 flex-shrink-0 ${n.color.replace('100', '500')}`} />
                  <div>
                    <p className="text-sm text-gray-700">{n.text}</p>
                    <p className="text-xs text-gray-400 mt-0.5">{n.time}</p>
                  </div>
                </div>
              ))}
            </div>
            <div className="px-4 py-3 border-t border-gray-100">
              <Link href="/notifications" className="text-sm text-blue-600 font-medium" onClick={() => setNotifOpen(false)}>
                View all notifications
              </Link>
            </div>
          </div>
        )}
      </div>

      {/* Admin avatar */}
      <div className="relative">
        <button
          onClick={() => { setDropdownOpen(!dropdownOpen); setNotifOpen(false) }}
          className="flex items-center gap-2 hover:bg-gray-50 rounded-lg px-2 py-1.5 transition-colors"
        >
          <div className="w-8 h-8 rounded-full bg-primary flex items-center justify-center text-white text-sm font-semibold">
            A
          </div>
          <span className="text-sm font-medium text-gray-700 hidden md:block">Admin</span>
          <ChevronDown className="w-4 h-4 text-gray-500 hidden md:block" />
        </button>

        {dropdownOpen && (
          <div className="absolute right-0 mt-2 w-48 bg-white rounded-xl shadow-xl border border-gray-100 z-50">
            <div className="px-4 py-3 border-b border-gray-100">
              <p className="text-sm font-semibold text-gray-800">Admin User</p>
              <p className="text-xs text-gray-500">admin@gora.com</p>
            </div>
            <Link
              href="/settings/general"
              className="flex items-center gap-2 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50"
              onClick={() => setDropdownOpen(false)}
            >
              <Settings className="w-4 h-4" /> Profile Settings
            </Link>
            <button
              onClick={() => router.push('/login')}
              className="w-full flex items-center gap-2 px-4 py-2.5 text-sm text-red-600 hover:bg-red-50"
            >
              <LogOut className="w-4 h-4" /> Logout
            </button>
          </div>
        )}
      </div>
    </header>
  )
}
