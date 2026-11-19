'use client'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ChevronRight } from 'lucide-react'

interface HeaderProps {
  title: string
}

/**
 * Page title bar under the topbar: the title on the left and a breadcrumb on
 * the right, as on the previous panel. The topbar itself lives in AdminShell.
 */
export function Header({ title }: HeaderProps) {
  // The zone admin panel has its own home.
  const home = usePathname()?.startsWith('/zone-panel') ? '/zone-panel' : '/dashboard'
  return (
    <div className="bg-white px-6 py-[13px] flex items-center justify-between gap-4 border-b border-[#e9ebec]"
      style={{ boxShadow: '0 1px 2px rgba(56,65,74,.15)' }}>
      <h4 className="text-[15px] font-bold uppercase text-[#495057] truncate">{title}</h4>
      <ol className="hidden sm:flex items-center gap-1 text-[13px] text-[#878a99] flex-shrink-0">
        <li><Link href={home} className="hover:text-[#405189]">Dashboard</Link></li>
        {title !== 'Dashboard' && (
          <>
            <li><ChevronRight className="w-3.5 h-3.5" /></li>
            <li className="text-[#495057]">{title}</li>
          </>
        )}
      </ol>
    </div>
  )
}
