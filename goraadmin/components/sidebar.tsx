'use client'
import { useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import {
  LayoutDashboard, Users, Car, Settings, Map, CreditCard, BarChart2,
  MessageSquare, Bell, Image, Gift, ChevronDown, ChevronRight,
  LogOut, Truck, FileText, Shield, HelpCircle, AlertCircle,
  CheckCircle, XCircle, Clock, DollarSign, Wallet, TrendingUp,
  Menu, X, User, Package
} from 'lucide-react'

interface NavItem {
  label: string
  href?: string
  icon: React.ElementType
  children?: { label: string; href: string; icon?: React.ElementType }[]
}

const navItems: NavItem[] = [
  { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { label: 'Users', href: '/users', icon: Users },
  {
    label: 'Drivers', icon: Car,
    children: [
      { label: 'All Drivers', href: '/drivers', icon: Car },
      { label: 'Pending Approval', href: '/drivers/pending', icon: Clock },
    ]
  },
  {
    label: 'Vehicles', icon: Truck,
    children: [
      { label: 'Vehicle Types', href: '/vehicles/types', icon: Package },
      { label: 'All Vehicles', href: '/vehicles/list', icon: Truck },
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
    ]
  },
  {
    label: 'Zones', icon: Map,
    children: [
      { label: 'Manage Zones', href: '/zones', icon: Map },
    ]
  },
  {
    label: 'Rides', icon: Car,
    children: [
      { label: 'All Rides', href: '/rides', icon: LayoutDashboard },
      { label: 'Ongoing', href: '/rides/ongoing', icon: Clock },
      { label: 'Scheduled', href: '/rides/scheduled', icon: CheckCircle },
      { label: 'Cancelled', href: '/rides/cancelled', icon: XCircle },
    ]
  },
  {
    label: 'Finance', icon: DollarSign,
    children: [
      { label: 'Withdrawals', href: '/finance/withdrawals', icon: DollarSign },
      { label: 'Wallet', href: '/finance/wallet', icon: Wallet },
      { label: 'Reports', href: '/finance/reports', icon: TrendingUp },
    ]
  },
  { label: 'Fleet Owners', href: '/fleet', icon: Truck },
  { label: 'Promo Codes', href: '/promos', icon: Gift },
  {
    label: 'Support', icon: HelpCircle,
    children: [
      { label: 'Tickets', href: '/support/tickets', icon: MessageSquare },
      { label: 'FAQ', href: '/support/faq', icon: FileText },
      { label: 'SOS Contacts', href: '/support/sos', icon: AlertCircle },
    ]
  },
  { label: 'Notifications', href: '/notifications', icon: Bell },
  { label: 'Banners', href: '/banners', icon: Image },
  {
    label: 'Settings', icon: Settings,
    children: [
      { label: 'General', href: '/settings/general', icon: Settings },
      { label: 'Payment', href: '/settings/payment', icon: CreditCard },
      { label: 'Maps', href: '/settings/maps', icon: Map },
      { label: 'SMS', href: '/settings/sms', icon: MessageSquare },
      { label: 'Mail', href: '/settings/mail', icon: FileText },
      { label: 'Firebase', href: '/settings/firebase', icon: Bell },
    ]
  },
]

export function Sidebar() {
  const pathname = usePathname()
  const router = useRouter()
  const [openSections, setOpenSections] = useState<string[]>(['Drivers', 'Services', 'Rides', 'Finance', 'Support', 'Settings', 'Vehicles', 'Zones'])
  const [mobileOpen, setMobileOpen] = useState(false)

  const toggleSection = (label: string) => {
    setOpenSections(prev =>
      prev.includes(label) ? prev.filter(s => s !== label) : [...prev, label]
    )
  }

  const isActive = (href: string) => pathname === href || pathname.startsWith(href + '/')
  const isSectionActive = (item: NavItem) => {
    if (item.href) return isActive(item.href)
    return item.children?.some(c => isActive(c.href)) ?? false
  }

  const SidebarContent = () => (
    <div className="flex flex-col h-full">
      {/* Logo */}
      <div className="px-4 py-5 border-b border-blue-800">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 bg-white rounded-lg flex items-center justify-center text-xl">🚖</div>
          <div>
            <h1 className="text-white font-bold text-base leading-tight">GORA ADMIN</h1>
            <p className="text-blue-300 text-xs">Management Panel</p>
          </div>
        </div>
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto py-3 px-2">
        {navItems.map(item => (
          <div key={item.label} className="mb-0.5">
            {item.href ? (
              <Link
                href={item.href}
                onClick={() => setMobileOpen(false)}
                className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                  isSectionActive(item)
                    ? 'bg-white/20 text-white'
                    : 'text-blue-200 hover:bg-white/10 hover:text-white'
                }`}
              >
                <item.icon className="w-4.5 h-4.5 w-5 h-5 flex-shrink-0" />
                <span>{item.label}</span>
              </Link>
            ) : (
              <>
                <button
                  onClick={() => toggleSection(item.label)}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all ${
                    isSectionActive(item)
                      ? 'text-white'
                      : 'text-blue-200 hover:bg-white/10 hover:text-white'
                  }`}
                >
                  <item.icon className="w-5 h-5 flex-shrink-0" />
                  <span className="flex-1 text-left">{item.label}</span>
                  {openSections.includes(item.label)
                    ? <ChevronDown className="w-4 h-4" />
                    : <ChevronRight className="w-4 h-4" />
                  }
                </button>
                {openSections.includes(item.label) && item.children && (
                  <div className="ml-3 pl-3 border-l border-blue-700 mt-0.5 space-y-0.5">
                    {item.children.map(child => (
                      <Link
                        key={child.href}
                        href={child.href}
                        onClick={() => setMobileOpen(false)}
                        className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm transition-all ${
                          isActive(child.href)
                            ? 'bg-white/20 text-white font-medium'
                            : 'text-blue-300 hover:bg-white/10 hover:text-white'
                        }`}
                      >
                        {child.icon && <child.icon className="w-4 h-4 flex-shrink-0" />}
                        <span>{child.label}</span>
                      </Link>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>
        ))}
      </nav>

      {/* Logout */}
      <div className="p-3 border-t border-blue-800">
        <div className="flex items-center gap-3 px-3 py-2 mb-2">
          <div className="w-8 h-8 rounded-full bg-blue-700 flex items-center justify-center">
            <User className="w-4 h-4 text-blue-200" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-white text-sm font-medium truncate">Admin User</p>
            <p className="text-blue-300 text-xs truncate">admin@gora.com</p>
          </div>
        </div>
        <button
          onClick={() => router.push('/login')}
          className="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-blue-200 hover:bg-white/10 hover:text-white text-sm transition-all"
        >
          <LogOut className="w-5 h-5" />
          <span>Logout</span>
        </button>
      </div>
    </div>
  )

  return (
    <>
      {/* Mobile hamburger */}
      <button
        className="fixed top-4 left-4 z-50 lg:hidden bg-primary text-white w-10 h-10 rounded-lg flex items-center justify-center shadow-lg"
        onClick={() => setMobileOpen(!mobileOpen)}
      >
        {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
      </button>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div className="fixed inset-0 z-40 lg:hidden" onClick={() => setMobileOpen(false)}>
          <div className="absolute inset-0 bg-black/50" />
        </div>
      )}

      {/* Mobile sidebar */}
      <aside
        className={`fixed top-0 left-0 h-full w-64 z-40 lg:hidden transition-transform duration-300 ${mobileOpen ? 'translate-x-0' : '-translate-x-full'}`}
        style={{ background: '#1565C0' }}
      >
        <SidebarContent />
      </aside>

      {/* Desktop sidebar */}
      <aside className="hidden lg:flex flex-col w-64 fixed top-0 left-0 h-full" style={{ background: '#1565C0' }}>
        <SidebarContent />
      </aside>
    </>
  )
}
