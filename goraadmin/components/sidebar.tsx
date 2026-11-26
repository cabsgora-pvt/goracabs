'use client'
import { useState } from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useFranchiseMode } from './franchise-mode'
import { useAdminAlerts, type AlertCounts } from './admin-alerts'
import {
  LayoutDashboard, Users, Car, Settings, Map, CreditCard, BarChart2,
  MessageSquare, Bell, Image, Gift, ChevronRight,
  Truck, FileText, HelpCircle, AlertCircle,
  CheckCircle, XCircle, Clock, DollarSign, Wallet, TrendingUp,
  Package, Zap, UserCheck, MapPin, Smartphone, Building2, BadgeIndianRupee, Inbox, Sparkles, FileCheck, ScrollText
} from 'lucide-react'

interface NavItem {
  label: string
  href?: string
  icon: React.ElementType
  children?: { label: string; href: string; icon?: React.ElementType }[]
}

// Same pages and links as before, grouped under section titles the way the
// previous panel's menu was ("MENU", "MANAGEMENT" ...).
const navSections: { title: string; items: NavItem[] }[] = [
  {
    title: 'Menu',
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Users', href: '/users', icon: Users },
      {
        label: 'Drivers', icon: Car,
        children: [
          { label: 'All Drivers', href: '/drivers', icon: Car },
          { label: 'Pending Approval', href: '/drivers/pending', icon: Clock },
        ]
      },
      { label: 'Fleet Owners', href: '/fleet', icon: Truck },
      { label: 'Account Requests', href: '/account-requests', icon: Inbox },
      { label: 'Needs Review', href: '/review', icon: AlertCircle },
    ],
  },
  {
    title: 'Trips',
    items: [
      {
        label: 'Rides', icon: Car,
        children: [
          { label: 'All Rides', href: '/rides', icon: LayoutDashboard },
          { label: 'Ongoing', href: '/rides/ongoing', icon: Clock },
          { label: 'Outstation', href: '/rides/outstation', icon: MapPin },
          { label: 'Rental', href: '/rides/rental', icon: Clock },
          { label: 'Hire a Driver', href: '/rides/hire', icon: UserCheck },
          { label: 'Delivery', href: '/rides/delivery', icon: Package },
          { label: 'Live Deliveries', href: '/rides/delivery/live', icon: Map },
          { label: 'Scheduled', href: '/rides/scheduled', icon: CheckCircle },
          { label: 'Cancelled', href: '/rides/cancelled', icon: XCircle },
        ]
      },
      {
        label: 'Services', icon: Settings,
        children: [
          { label: 'Overview', href: '/services', icon: BarChart2 },
          { label: 'Taxi', href: '/services/taxi', icon: Car },
          { label: 'Rental', href: '/services/rental', icon: Clock },
          { label: 'Outstation', href: '/services/outstation', icon: Map },
          { label: 'Delivery', href: '/services/delivery', icon: Package },
          { label: 'Hire a Driver', href: '/services/hire-driver', icon: UserCheck },
        ]
      },
    ],
  },
  {
    title: 'Masters',
    items: [
      {
        label: 'Vehicles', icon: Truck,
        children: [
          { label: 'Vehicle Types', href: '/vehicles/types', icon: Package },
          { label: 'All Vehicles', href: '/vehicles/list', icon: Truck },
        ]
      },
      {
        label: 'Zones', icon: Map,
        children: [
          { label: 'Manage Zones', href: '/zones', icon: Map },
          { label: 'Surge Pricing', href: '/zones/surge', icon: Zap },
        ]
      },
      { label: 'Driver Documents', href: '/document-types', icon: FileCheck },
      { label: 'Ride Preferences', href: '/ride-preferences', icon: Sparkles },
    ],
  },
  {
    title: 'Franchise',
    items: [
      { label: 'Zone Admins', href: '/zone-admins', icon: Building2 },
      { label: 'Subscription Plans', href: '/zone-plans', icon: BadgeIndianRupee },
      { label: 'Franchise Report', href: '/zone-admins/report', icon: BarChart2 },
    ],
  },
  {
    title: 'Finance & Promotions',
    items: [
      {
        label: 'Finance', icon: DollarSign,
        children: [
          { label: 'Withdrawals', href: '/finance/withdrawals', icon: DollarSign },
          { label: 'Wallet', href: '/finance/wallet', icon: Wallet },
          { label: 'Reports', href: '/finance/reports', icon: TrendingUp },
        ]
      },
      { label: 'Promo Codes', href: '/promos', icon: Gift },
      { label: 'Banners', href: '/banners', icon: Image },
      { label: 'Notifications', href: '/notifications', icon: Bell },
    ],
  },
  {
    title: 'Others',
    items: [
      {
        label: 'Support', icon: HelpCircle,
        children: [
          { label: 'Tickets', href: '/support/tickets', icon: FileText },
          { label: 'Support Chat', href: '/support/chats', icon: MessageSquare },
          { label: 'FAQ', href: '/support/faq', icon: HelpCircle },
          { label: 'SOS Alerts & Contacts', href: '/support/sos', icon: AlertCircle },
        ]
      },
      {
        label: 'Settings', icon: Settings,
        children: [
          { label: 'User App', href: '/settings/user-app', icon: Smartphone },
          { label: 'Driver App', href: '/settings/driver-app', icon: Car },
          { label: 'General', href: '/settings/general', icon: Settings },
          { label: 'Payment', href: '/settings/payment', icon: CreditCard },
          { label: 'Maps', href: '/settings/maps', icon: Map },
          { label: 'SMS', href: '/settings/sms', icon: MessageSquare },
          { label: 'Mail', href: '/settings/mail', icon: FileText },
          { label: 'Firebase', href: '/settings/firebase', icon: Bell },
        ]
      },
      { label: 'Audit Log', href: '/audit-log', icon: ScrollText },
    ],
  },
]

// Menu badges: what is waiting behind each link (GET /api/admin/alerts).
const BADGES: Record<string, (c: AlertCounts) => number> = {
  '/account-requests': c => c.accountRequests,
  '/review': c => c.needsReview,
  '/drivers/pending': c => c.driversPending,
  '/finance/withdrawals': c => c.withdrawalsPending,
  '/support/tickets': c => c.ticketsOpen,
  '/support/sos': c => c.sosActive + c.sosAcknowledged,
}

/** Brand colour of the previous panel's side menu. */
export const SIDE_MENU = '#405189'

interface SidebarProps {
  /** Desktop: icon-only rail. */
  collapsed: boolean
  /** Phone: drawer shown. */
  mobileOpen: boolean
  onCloseMobile: () => void
}

export function Sidebar({ collapsed, mobileOpen, onCloseMobile }: SidebarProps) {
  const pathname = usePathname()
  // The Franchise section shows only while franchise mode is on.
  const { enabled: franchiseOn } = useFranchiseMode()
  const sections = navSections.filter(s => s.title !== 'Franchise' || franchiseOn === true)
  const matches = (href: string) => pathname === href || pathname.startsWith(href + '/')
  // The most specific link wins: /zone-admins/report lights "Franchise Report",
  // not "Zone Admins" as well.
  const allHrefs = navSections.flatMap(s => s.items.flatMap(i => i.href ? [i.href] : (i.children || []).map(c => c.href)))
  const isActive = (href: string) => matches(href) && !allHrefs.some(h => h.length > href.length && h.startsWith(href) && matches(h))
  const isSectionActive = (item: NavItem) =>
    item.href ? isActive(item.href) : (item.children?.some(c => isActive(c.href)) ?? false)

  // Open the group holding the current page; the rest start closed, as before.
  const [open, setOpen] = useState<string[]>(() =>
    navSections.flatMap(s => s.items).filter(i => i.children && isSectionActive(i)).map(i => i.label))
  const toggle = (label: string) =>
    setOpen(prev => prev.includes(label) ? prev.filter(s => s !== label) : [...prev, label])

  // Folded to icons: hovering the rail opens the full menu over the page.
  const [hovered, setHovered] = useState(false)
  const rail = collapsed && !hovered

  // Badges from the one alerts poll (components/admin-alerts, every 10 s).
  const { counts } = useAdminAlerts()
  const badge = (href: string) => (counts ? BADGES[href]?.(counts) || 0 : 0)
  const badgeEl = (n: number, rail: boolean, red = true) => n > 0 && (
    <span className={`${rail ? 'absolute ml-6 -mt-4' : 'ml-1'} min-w-[18px] h-[18px] px-1 rounded-full ${red ? 'bg-red-500' : 'bg-amber-500'} text-white text-[10px] font-bold flex items-center justify-center`}>{n > 99 ? '99+' : n}</span>
  )

  const content = (rail: boolean) => (
    <div className="flex flex-col h-full">
      {/* Logo box — 70px, the topbar's height */}
      <Link href="/dashboard" className="h-[70px] flex items-center justify-center gap-2 px-5 flex-shrink-0"
        onClick={onCloseMobile}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/gora-logo.png" alt="Gora" className={rail ? 'h-6 w-auto' : 'h-8 w-auto'} />
        {!rail && <span className="text-[22px] font-bold tracking-wide" style={{ color: SIDE_MENU }}>GORA</span>}
      </Link>

      <nav className="flex-1 overflow-y-auto pb-6">
        {sections.map(section => (
          <div key={section.title}>
            {rail
              ? <div className="mx-auto my-3 w-6 border-t border-[#e9ebec]" />
              : <p className="px-5 pt-4 pb-2 text-[11px] font-semibold uppercase tracking-[0.05em] text-[#878a99]">{section.title}</p>}
            {section.items.map(item => {
              const active = isSectionActive(item)
              const expanded = open.includes(item.label)
              const rowBase = `relative flex items-center ${rail ? 'justify-center px-0' : 'px-6'} py-[10px] text-[15px] w-full hover:bg-[#f3f3f9]`
              if (item.href) {
                return (
                  <Link key={item.label} href={item.href} onClick={onCloseMobile} title={rail ? item.label : undefined}
                    className={`${rowBase} ${active ? 'text-white font-medium' : 'text-[#6d7080] hover:text-[#405189]'}`}
                    style={active ? { backgroundColor: SIDE_MENU } : undefined}>
                    <item.icon className={`w-[18px] h-[18px] flex-shrink-0 ${rail ? '' : 'mr-[10px]'}`} />
                    {!rail && <span className="truncate flex-1">{item.label}</span>}
                    {badgeEl(badge(item.href), rail)}
                  </Link>
                )
              }
              return (
                <div key={item.label}>
                  <button type="button" onClick={() => toggle(item.label)} title={rail ? item.label : undefined}
                    className={`${rowBase} ${active ? 'font-medium' : ''} text-left`}
                    style={{ color: active ? SIDE_MENU : '#6d7080' }}>
                    <item.icon className={`w-[18px] h-[18px] flex-shrink-0 ${rail ? '' : 'mr-[10px]'}`} />
                    {!rail && <span className="flex-1 truncate">{item.label}</span>}
                    {!expanded && badgeEl((item.children || []).reduce((t, c) => t + badge(c.href), 0), rail)}
                    {!rail && <ChevronRight className={`w-4 h-4 transition-transform ${expanded ? 'rotate-90' : ''}`} />}
                  </button>
                  {expanded && !rail && item.children && (
                    <div className="pb-1">
                      {item.children.map(child => {
                        const on = isActive(child.href)
                        return (
                          <Link key={child.href} href={child.href} onClick={onCloseMobile}
                            className={`relative flex items-center pl-[52px] pr-6 py-[7px] text-[13.5px] ${on ? 'font-semibold' : 'hover:text-[#405189]'}`}
                            style={{ color: on ? SIDE_MENU : '#6d7080' }}>
                            <span className="absolute left-[30px] top-1/2 -translate-y-1/2 w-[6px] h-[6px] rounded-full border"
                              style={{ borderColor: on ? SIDE_MENU : '#adb5bd', backgroundColor: on ? SIDE_MENU : 'transparent' }} />
                            <span className="truncate flex-1">{child.label}</span>
                            {badgeEl(badge(child.href), false, child.href !== '/support/sos' || !!counts?.sosActive)}
                          </Link>
                        )
                      })}
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        ))}
      </nav>
    </div>
  )

  return (
    <>
      {/* Phone drawer */}
      {mobileOpen && <div className="fixed inset-0 z-40 bg-black/40 lg:hidden" onClick={onCloseMobile} />}
      <aside className={`fixed top-0 left-0 h-full w-[250px] z-50 bg-white border-r border-[#e9ebec] shadow-lg lg:hidden transition-transform duration-300 ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}`}>
        {content(false)}
      </aside>

      {/* Desktop */}
      <aside className={`hidden lg:flex flex-col fixed top-0 left-0 h-full z-30 bg-white border-r border-[#e9ebec] transition-[width] duration-200 ${rail ? 'w-[70px]' : 'w-[250px]'}`}
        onMouseEnter={() => { if (collapsed) setHovered(true) }}
        onMouseLeave={() => setHovered(false)}
        style={{ boxShadow: collapsed && hovered ? '4px 0 18px rgba(15,34,58,.18)' : '0 2px 4px rgba(15,34,58,.12)' }}>
        {content(rail)}
      </aside>
    </>
  )
}
