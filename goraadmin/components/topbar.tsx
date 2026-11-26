'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Bell, ChevronDown, LogOut, Settings, Home, Users, FileText, Menu, Maximize, Moon, Sun } from 'lucide-react'
import { SIDE_MENU } from './sidebar'
import { useAdminAlerts } from './admin-alerts'

const ALERT_ROWS = [
  { key: 'sosActive', label: 'SOS waiting', href: '/support/sos' },
  { key: 'ticketsOpen', label: 'Open tickets', href: '/support/tickets' },
  { key: 'driversPending', label: 'Driver approvals', href: '/drivers/pending' },
  { key: 'withdrawalsPending', label: 'Withdrawals', href: '/finance/withdrawals' },
  { key: 'accountRequests', label: 'Account requests', href: '/account-requests' },
  { key: 'needsReview', label: 'Needs review', href: '/review' },
]
const KIND_DOT: Record<string, string> = { sos: 'bg-red-600', ticket: 'bg-orange-500', driver: 'bg-yellow-500', withdrawal: 'bg-blue-500', request: 'bg-purple-500' }
function ago(at: string) {
  const s = Math.max(0, Math.round((Date.now() - new Date(at).getTime()) / 1000))
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  return `${Math.floor(s / 86400)}d ago`
}

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
  const { counts, items, error } = useAdminAlerts()
  const alertTotal = counts ? ALERT_ROWS.reduce((t, r) => t + ((counts as any)[r.key] || 0), 0) : 0

  // Sign out: clear the httpOnly admin_token cookie server-side (JS cannot),
  // drop any token an older build left in localStorage, then go to /login.
  const logout = async () => {
    setDropdownOpen(false)
    try { await fetch('/api/auth/logout', { method: 'POST', credentials: 'same-origin' }) } catch {}
    try { localStorage.removeItem('admin_token') } catch {}
    router.replace('/login')
    router.refresh()
  }

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

      {/* Alerts — live counts from /api/admin/alerts (components/admin-alerts) */}
      <div className="relative">
        <button
          type="button"
          aria-label="Alerts"
          onClick={() => { setNotifOpen(!notifOpen); setDropdownOpen(false) }}
          className="relative w-10 h-10 flex items-center justify-center rounded-full text-[#878a99] hover:bg-[#f3f3f9]"
        >
          <Bell className={`w-[19px] h-[19px] ${counts?.sosActive ? 'text-red-600 animate-pulse' : ''}`} />
          {alertTotal > 0 && (
            <span className={`absolute top-0.5 right-0.5 min-w-[16px] h-4 px-1 rounded-full text-white text-[10px] font-bold flex items-center justify-center ${counts?.sosActive ? 'bg-red-600' : 'bg-red-500'}`}>
              {alertTotal > 99 ? '99+' : alertTotal}
            </span>
          )}
        </button>
        {notifOpen && (
          <div className="absolute right-0 mt-2 w-80 bg-white rounded shadow-xl border border-[#e9ebec] z-50">
            <div className="px-4 py-3 text-white rounded-t" style={{ backgroundColor: SIDE_MENU }}>
              <p className="font-semibold">Needs attention</p>
            </div>
            <div className="grid grid-cols-2 gap-px bg-gray-100 border-b border-gray-100">
              {ALERT_ROWS.map(r => (
                <Link key={r.key} href={r.href} onClick={() => setNotifOpen(false)}
                  className={`bg-white px-3 py-2 text-xs flex items-center justify-between hover:bg-gray-50 ${r.key === 'sosActive' && counts?.sosActive ? 'text-red-700 font-semibold' : 'text-gray-600'}`}>
                  <span>{r.label}</span>
                  <span className="font-bold">{counts ? (counts as any)[r.key] : '…'}</span>
                </Link>
              ))}
            </div>
            <div className="divide-y divide-gray-50 max-h-72 overflow-y-auto">
              {items.map(n => (
                <Link key={n.kind + n.id} href={n.href} onClick={() => setNotifOpen(false)} className="px-4 py-3 hover:bg-gray-50 flex items-start gap-3">
                  <div className={`w-2 h-2 rounded-full mt-2 flex-shrink-0 ${KIND_DOT[n.kind] || 'bg-gray-400'}`} />
                  <div>
                    <p className="text-sm text-gray-700">{n.text}</p>
                    <p className="text-xs text-gray-400 mt-0.5">{ago(n.at)}</p>
                  </div>
                </Link>
              ))}
              {counts && items.length === 0 && <p className="px-4 py-6 text-sm text-gray-400 text-center">Nothing waiting. All clear.</p>}
              {error && <p className="px-4 py-2 text-xs text-red-500">Could not refresh alerts.</p>}
            </div>
            <div className="px-4 py-3 border-t border-gray-100">
              <Link href="/review" className="text-sm text-blue-600 font-medium" onClick={() => setNotifOpen(false)}>
                Open the review queue
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
              onClick={logout}
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
