'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Bell, ChevronDown, LogOut, Settings, Home, Users, FileText, Menu, Maximize, Moon, Sun } from 'lucide-react'
import { SIDE_MENU } from './sidebar'

// Module tabs across the top, as on the previous panel (Home · Users ·
// Settings · Masters). Each opens a page that already exists.
const modules = [
  { label: 'Home', href: '/dashboard', icon: Home, match: ['/dashboard', '/rides', '/services', '/finance', '/promos', '/banners', '/notifications'] },
  { label: 'Users', href: '/users', icon: Users, match: ['/users', '/drivers', '/fleet', '/zone-admins', '/zone-plans'] },
  { label: 'Settings', href: '/settings/general', icon: Settings, match: ['/settings', '/support'] },
  { label: 'Masters', href: '/vehicles/types', icon: FileText, match: ['/vehicles', '/zones'] },
]

export function Topbar({ onMenu }: { onMenu: () => void }) {
  // Light / dark theme, remembered in this browser.
  const [dark, setDark] = useState(false)
  useEffect(() => {
    let saved = ''
    try { saved = localStorage.getItem('gora-admin-theme') || '' } catch {}
    const on = saved === 'dark'
    setDark(on)
    document.documentElement.classList.toggle('dark', on)
  }, [])
  const toggleTheme = () => {
    const on = !dark
    setDark(on)
    document.documentElement.classList.toggle('dark', on)
    try { localStorage.setItem('gora-admin-theme', on ? 'dark' : 'light') } catch {}
  }
  const router = useRouter()
  const pathname = usePathname()
  const [dropdownOpen, setDropdownOpen] = useState(false)
  const [notifOpen, setNotifOpen] = useState(false)

  const fullscreen = () => {
    if (document.fullscreenElement) document.exitFullscreen?.()
    else document.documentElement.requestFullscreen?.().catch(() => {})
  }

  return (
    <header className="admin-topbar h-[70px] flex-shrink-0 bg-white flex items-center pr-4 lg:pr-6 sticky top-0 z-20"
      style={{ boxShadow: '0 1px 2px rgba(56,65,74,.15)' }}>
      <button type="button" onClick={onMenu} aria-label="Toggle menu"
        className="h-[70px] px-4 lg:px-5 text-[#878a99] hover:text-[#405189]">
        <Menu className="w-[22px] h-[22px]" />
      </button>

      {/* Module tabs */}
      <nav className="hidden md:flex items-stretch h-full">
        {modules.map(m => {
          const on = m.match.some(p => pathname === p || pathname.startsWith(p + '/'))
          return (
            <Link key={m.label} href={m.href}
              className="relative flex items-center gap-2 px-4 text-[14px] font-medium"
              style={{ color: on ? SIDE_MENU : '#6d7080' }}>
              <m.icon className="w-[17px] h-[17px]" />
              {m.label}
              {on && <span className="absolute left-3 right-3 bottom-0 h-[3px] rounded-t" style={{ backgroundColor: SIDE_MENU }} />}
            </Link>
          )
        })}
      </nav>

      <div className="flex-1" />

      {/* Fullscreen */}
      <button type="button" onClick={toggleTheme} aria-label={dark ? 'Light mode' : 'Dark mode'} title={dark ? 'Light mode' : 'Dark mode'}
        className="hidden sm:flex h-10 w-10 items-center justify-center rounded-full text-[#878a99] hover:text-[#405189] hover:bg-[#f3f3f9]">
        {dark ? <Sun className="w-[19px] h-[19px]" /> : <Moon className="w-[19px] h-[19px]" />}
      </button>
      <button type="button" onClick={fullscreen} aria-label="Fullscreen"
        className="hidden sm:flex w-10 h-10 items-center justify-center rounded-full text-[#878a99] hover:bg-[#f3f3f9]">
        <Maximize className="w-[19px] h-[19px]" />
      </button>

      {/* Notifications */}
      <div className="relative">
        <button
          onClick={() => { setNotifOpen(!notifOpen); setDropdownOpen(false) }}
          className="relative w-10 h-10 flex items-center justify-center rounded-full text-[#878a99] hover:bg-[#f3f3f9]"
        >
          <Bell className="w-[19px] h-[19px]" />
          <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-red-500 rounded-full" />
        </button>
        {notifOpen && (
          <div className="absolute right-0 mt-2 w-80 bg-white rounded shadow-xl border border-[#e9ebec] z-50">
            <div className="px-4 py-3 text-white rounded-t" style={{ backgroundColor: SIDE_MENU }}>
              <p className="font-semibold">Notifications</p>
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

      {/* Admin profile — the previous panel's avatar, name and role block */}
      <div className="relative ml-2">
        <button
          onClick={() => { setDropdownOpen(!dropdownOpen); setNotifOpen(false) }}
          className="h-[70px] flex items-center gap-2.5 px-3 bg-[#f3f3f9]/70 hover:bg-[#f3f3f9]"
        >
          <div className="w-8 h-8 rounded-full flex items-center justify-center text-white text-sm font-semibold"
            style={{ backgroundColor: SIDE_MENU }}>
            A
          </div>
          <span className="hidden md:flex flex-col items-start leading-tight">
            <span className="text-[13px] font-semibold text-[#495057]">Admin</span>
            <span className="text-[12px] text-[#878a99]">Super Admin</span>
          </span>
          <ChevronDown className="w-4 h-4 text-[#878a99] hidden md:block" />
        </button>

        {dropdownOpen && (
          <div className="absolute right-0 mt-1 w-48 bg-white rounded shadow-xl border border-[#e9ebec] z-50">
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
