'use client'
import { useState } from 'react'
import { Sidebar } from './sidebar'
import { Topbar } from './topbar'

/** Sidebar + topbar frame of every admin page, in the previous panel's layout. */
export function AdminShell({ children }: { children: React.ReactNode }) {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)

  const onMenu = () => {
    // The hamburger folds the desktop menu to icons; on a phone it opens the drawer.
    if (window.matchMedia('(min-width: 1024px)').matches) setCollapsed(c => !c)
    else setMobileOpen(o => !o)
  }

  return (
    <div className="h-screen overflow-hidden" style={{ backgroundColor: '#f3f3f9' }}>
      <Sidebar collapsed={collapsed} mobileOpen={mobileOpen} onCloseMobile={() => setMobileOpen(false)} />
      <div className={`h-full flex flex-col ${collapsed ? 'lg:pl-[70px]' : 'lg:pl-[250px]'}`}>
        <Topbar onMenu={onMenu} />
        <div className="flex-1 overflow-y-auto">{children}</div>
      </div>
    </div>
  )
}
