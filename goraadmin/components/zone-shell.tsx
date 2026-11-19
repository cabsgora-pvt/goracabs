'use client'
import { createContext, useCallback, useContext, useEffect, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import {
  LayoutDashboard, Car, Receipt, IndianRupee, UserCircle, LogOut, Menu, Lock, Map as MapIcon,
  LifeBuoy, Ticket, FileBarChart, Wallet, Users, Eye,
} from 'lucide-react'
import { daysLeft, fmtDate } from '@/lib/zone-admin-ui'

// Frame of the zone admin (franchise) panel: the same look as the super admin
// panel, with only the pages this zone admin's plan — or this staff member's
// permissions — include. A blocked account or a lapsed subscription (after the
// read-only grace days) shows a lock screen.

const SIDE = '#405189'
type NavItem = { label: string; href: string; icon: React.ElementType; feature?: string; ownerOnly?: boolean }
const nav: NavItem[] = [
  { label: 'Dashboard', href: '/zone-panel', icon: LayoutDashboard },
  { label: 'Live Map', href: '/zone-panel/live', icon: MapIcon, feature: 'live_map' },
  { label: 'Drivers', href: '/zone-panel/drivers', icon: Car, feature: 'drivers' },
  { label: 'Rides', href: '/zone-panel/rides', icon: Receipt },
  { label: 'Zone Pricing', href: '/zone-panel/pricing', icon: IndianRupee, feature: 'pricing' },
  { label: 'Support & SOS', href: '/zone-panel/support', icon: LifeBuoy, feature: 'support' },
  { label: 'Promo Codes', href: '/zone-panel/promos', icon: Ticket, feature: 'promos' },
  { label: 'Reports', href: '/zone-panel/reports', icon: FileBarChart, feature: 'reports' },
  { label: 'Earnings', href: '/zone-panel/earnings', icon: Wallet, ownerOnly: true },
  { label: 'Staff', href: '/zone-panel/staff', icon: Users, feature: 'staff', ownerOnly: true },
  { label: 'My Profile', href: '/zone-panel/profile', icon: UserCircle },
]

export type ZoneMe = {
  _id: string; name: string; email: string; phone?: string; businessName?: string; address?: string; gstNumber?: string
  zones: { _id: string; name: string; supportPhone?: string }[]; subscriptionEndAt: string | null
  payments: any[]; payouts: any[]; totalPaid: number; access: string; revenueSharePercent: number; priceChangeLimitPct: number
}
export type ZoneSession = {
  features: string[]; isOwner: boolean; readOnly: boolean
  actor: { type: string; id: string; name: string }; impersonatedBy: string | null
}
const Ctx = createContext<{ me: ZoneMe; session: ZoneSession; reload: () => void } | null>(null)
export const useZoneAdmin = () => useContext(Ctx)?.me ?? null
export const useZoneSession = () => useContext(Ctx)?.session ?? null
export const useZoneReload = () => useContext(Ctx)?.reload ?? (() => {})

/** fetch for zone panel pages: a 401 sends the admin back to sign-in. */
export async function zoneFetch(url: string, init?: RequestInit) {
  const res = await fetch(url, init)
  if (res.status === 401) {
    window.location.href = '/zone-panel/login'
    throw new Error('signed out')
  }
  return res
}

export function ZoneShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router = useRouter()
  const [data, setData] = useState<{ me: ZoneMe; session: ZoneSession } | null>(null)
  const [locked, setLocked] = useState<string | null>(null)
  const [mobileOpen, setMobileOpen] = useState(false)

  const load = useCallback(() => {
    fetch('/api/zone-admin/me').then(async r => {
      const d = await r.json().catch(() => ({}))
      if (r.status === 401) { router.replace('/zone-panel/login'); return }
      if (r.status === 403) { setLocked(d.error || 'Access stopped'); return }
      setData({ me: d.zoneAdmin, session: d.session })
    }).catch(() => setLocked('Could not reach the server. Check your connection.'))
  }, [router])
  useEffect(() => { load() }, [load])

  const logout = useCallback(async () => {
    await fetch('/api/zone-admin/logout', { method: 'POST' }).catch(() => {})
    router.replace('/zone-panel/login')
  }, [router])

  if (locked) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6" style={{ backgroundColor: '#f3f3f9' }}>
        <div className="bg-white rounded p-8 max-w-md text-center" style={{ boxShadow: '0 5px 10px rgba(30,32,37,.12)' }}>
          <div className="w-14 h-14 rounded-full bg-red-50 flex items-center justify-center mx-auto mb-4"><Lock className="w-7 h-7 text-red-500" /></div>
          <h4 className="text-[17px] font-semibold text-[#495057]">Zone panel locked</h4>
          <p className="text-[13px] text-gray-500 mt-2">{locked}</p>
          <button type="button" onClick={logout} className="mt-6 px-4 py-2 rounded text-white text-[13px]" style={{ backgroundColor: SIDE }}>Back to sign in</button>
        </div>
      </div>
    )
  }

  const me = data?.me, session = data?.session
  const items = nav.filter(n => (!n.feature || session?.features.includes(n.feature)) && (!n.ownerOnly || session?.isOwner))
  const left = daysLeft(me?.subscriptionEndAt)
  const isActive = (href: string) => href === '/zone-panel' ? pathname === href : pathname === href || pathname.startsWith(href + '/')
  const who = session?.actor.type === 'staff' ? 'Staff' : 'Zone Admin'

  const menu = (
    <div className="flex flex-col h-full">
      <Link href="/zone-panel" className="h-[70px] flex items-center justify-center gap-2 px-5 flex-shrink-0">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/gora-logo.png" alt="Gora" className="h-8 w-auto" />
        <span className="text-[22px] font-bold tracking-wide" style={{ color: SIDE }}>GORA</span>
      </Link>
      <p className="px-5 pt-2 pb-2 text-[11px] font-semibold uppercase tracking-[0.05em] text-[#878a99]">Zone Panel</p>
      <nav className="flex-1 overflow-y-auto">
        {items.map(n => {
          const on = isActive(n.href)
          return (
            <Link key={n.href} href={n.href} onClick={() => setMobileOpen(false)}
              className={`flex items-center px-6 py-[10px] text-[15px] ${on ? 'text-white font-medium' : 'text-[#6d7080] hover:text-[#405189]'}`}
              style={on ? { backgroundColor: SIDE } : undefined}>
              <n.icon className="w-[18px] h-[18px] mr-[10px]" />{n.label}
            </Link>
          )
        })}
      </nav>
      <button type="button" onClick={logout} className="flex items-center px-6 py-4 text-[14px] text-[#6d7080] hover:text-red-600 border-t border-[#e9ebec]">
        <LogOut className="w-[18px] h-[18px] mr-[10px]" /> Logout
      </button>
    </div>
  )

  return (
    <Ctx.Provider value={data ? { ...data, reload: load } : null}>
      <div className="h-screen overflow-hidden" style={{ backgroundColor: '#f3f3f9' }}>
        {mobileOpen && <div className="fixed inset-0 z-40 bg-black/40 lg:hidden" onClick={() => setMobileOpen(false)} />}
        <aside className={`fixed top-0 left-0 h-full w-[250px] z-50 bg-white border-r border-[#e9ebec] transition-transform lg:translate-x-0 ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}`}
          style={{ boxShadow: '0 2px 4px rgba(15,34,58,.12)' }}>
          {menu}
        </aside>
        <div className="h-full flex flex-col lg:pl-[250px]">
          <header className="h-[70px] flex-shrink-0 bg-white flex items-center pr-4 lg:pr-6" style={{ boxShadow: '0 1px 2px rgba(56,65,74,.15)' }}>
            <button type="button" onClick={() => setMobileOpen(o => !o)} className="h-[70px] px-4 lg:hidden text-[#878a99]" aria-label="Menu">
              <Menu className="w-[22px] h-[22px]" />
            </button>
            <div className="pl-2 lg:pl-6 flex-1 min-w-0">
              <p className="text-[14px] font-semibold text-[#495057] truncate">{me?.zones.map(z => z.name).join(', ') || '…'}</p>
              <p className="text-[12px] text-[#878a99]">Zone admin panel</p>
            </div>
            {me?.subscriptionEndAt && (
              <span className={`hidden sm:inline-flex mr-4 px-2.5 py-1 rounded text-[11px] font-semibold ${left !== null && left <= 7 ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'}`}>
                {left !== null && left <= 0 ? `Subscription ended ${fmtDate(me.subscriptionEndAt)}` : `Subscription till ${fmtDate(me.subscriptionEndAt)}`}{left !== null && left > 0 && left <= 7 ? ` · ${left}d left` : ''}
              </span>
            )}
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-full flex items-center justify-center text-white text-sm font-semibold" style={{ backgroundColor: SIDE }}>
                {session?.actor.name?.[0]?.toUpperCase() || 'Z'}
              </div>
              <span className="hidden md:flex flex-col leading-tight">
                <span className="text-[13px] font-semibold text-[#495057]">{session?.actor.type === 'super_admin' ? me?.name : session?.actor.name || ''}</span>
                <span className="text-[12px] text-[#878a99]">{who}</span>
              </span>
            </div>
          </header>
          {session?.impersonatedBy && (
            <div className="bg-[#405189] text-white text-[13px] px-6 py-2 flex items-center gap-2">
              <Eye className="w-4 h-4" /> You ({session.impersonatedBy}) are viewing {me?.name}&apos;s panel. Everything you do here is logged.
            </div>
          )}
          {session?.readOnly ? (
            <div className="bg-red-50 border-b border-red-200 text-red-700 text-[13px] px-6 py-2">
              Your subscription ended on {fmtDate(me?.subscriptionEndAt)}. The panel is read-only for a few days — renew with Gora to make changes.
            </div>
          ) : left !== null && left <= 7 && (
            <div className="bg-yellow-50 border-b border-yellow-200 text-yellow-800 text-[13px] px-6 py-2">
              Your subscription ends on {fmtDate(me?.subscriptionEndAt)} ({left <= 0 ? 'today' : `${left} day${left === 1 ? '' : 's'} left`}). Contact Gora to renew and keep access.
            </div>
          )}
          <div className="flex-1 overflow-y-auto">{data ? children : <div className="p-6 text-gray-400">Loading…</div>}</div>
        </div>
      </div>
    </Ctx.Provider>
  )
}
