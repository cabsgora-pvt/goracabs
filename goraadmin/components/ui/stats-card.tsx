'use client'
import { LucideIcon } from 'lucide-react'

interface StatsCardProps {
  icon: LucideIcon
  label: string
  value: string | number
  trend?: number
  iconColor?: string
  iconBg?: string
}

export function StatsCard({ icon: Icon, label, value, trend, iconColor = 'text-blue-600', iconBg = 'bg-blue-50' }: StatsCardProps) {
  return (
    <div className="bg-white rounded p-5 flex items-center gap-4" style={{ boxShadow: '0 1px 2px rgba(56,65,74,.15)' }}>
      <div className="flex-1 min-w-0">
        <p className="text-[13px] font-medium uppercase text-[#878a99] truncate">{label}</p>
        <p className="text-[22px] font-semibold text-[#495057] mt-3">{value}</p>
        {trend !== undefined && (
          <p className={`text-xs mt-1 font-medium ${trend >= 0 ? 'text-green-600' : 'text-red-500'}`}>
            {trend >= 0 ? '▲' : '▼'} {Math.abs(trend)}% vs yesterday
          </p>
        )}
      </div>
      <div className={`w-12 h-12 rounded ${iconBg} flex items-center justify-center flex-shrink-0`}>
        <Icon className={`w-6 h-6 ${iconColor}`} />
      </div>
    </div>
  )
}
