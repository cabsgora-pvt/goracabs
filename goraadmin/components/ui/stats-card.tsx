'use client'
import Link from 'next/link'
import { LucideIcon, ArrowRight } from 'lucide-react'

interface StatsCardProps {
  icon: LucideIcon
  label: string
  value: string | number
  trend?: number
  iconColor?: string
  iconBg?: string
  /** Makes the whole card a link to the page behind the number. */
  href?: string
  /** Small line under the value ("₹1,240 commission"). */
  sub?: string
}

export function StatsCard({ icon: Icon, label, value, trend, iconColor = 'text-blue-600', iconBg = 'bg-blue-50', href, sub }: StatsCardProps) {
  const body = (
    <div className={`stats-card bg-white rounded p-5 flex items-center gap-4 h-full ${href ? 'transition hover:-translate-y-0.5 hover:shadow-md cursor-pointer group' : ''}`}
      style={{ boxShadow: '0 1px 2px rgba(56,65,74,.15)' }}>
      <div className="flex-1 min-w-0">
        <p className="text-[13px] font-medium uppercase text-[#878a99] truncate">{label}</p>
        <p className="text-[22px] font-semibold text-[#495057] mt-3">{value}</p>
        {sub && <p className="text-xs text-[#878a99] mt-1 truncate">{sub}</p>}
        {trend !== undefined && (
          <p className={`text-xs mt-1 font-medium ${trend >= 0 ? 'text-green-600' : 'text-red-500'}`}>
            {trend >= 0 ? '▲' : '▼'} {Math.abs(trend)}% vs yesterday
          </p>
        )}
        {href && <p className="text-[11px] text-primary mt-1.5 opacity-0 group-hover:opacity-100 transition flex items-center gap-1">View <ArrowRight className="w-3 h-3" /></p>}
      </div>
      <div className={`w-12 h-12 rounded ${iconBg} flex items-center justify-center flex-shrink-0`}>
        <Icon className={`w-6 h-6 ${iconColor}`} />
      </div>
    </div>
  )
  return href ? <Link href={href} className="block h-full">{body}</Link> : body
}
