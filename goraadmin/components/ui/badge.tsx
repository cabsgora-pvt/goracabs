'use client'

interface BadgeProps {
  status: string
  className?: string
}

export function Badge({ status, className = '' }: BadgeProps) {
  const s = status?.toLowerCase()
  let color = 'bg-gray-100 text-gray-600'

  if (['active', 'approved', 'completed', 'verified', 'success'].includes(s)) {
    color = 'bg-green-100 text-green-700'
  } else if (['pending', 'scheduled', 'in-progress', 'processing'].includes(s)) {
    color = 'bg-yellow-100 text-yellow-700'
  } else if (['blocked', 'rejected', 'cancelled', 'expired', 'inactive', 'failed'].includes(s)) {
    color = 'bg-red-100 text-red-700'
  } else if (['ongoing', 'info', 'open'].includes(s)) {
    color = 'bg-blue-100 text-blue-700'
  } else if (['high'].includes(s)) {
    color = 'bg-red-100 text-red-700'
  } else if (['medium'].includes(s)) {
    color = 'bg-yellow-100 text-yellow-700'
  } else if (['low'].includes(s)) {
    color = 'bg-green-100 text-green-700'
  }

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium capitalize ${color} ${className}`}>
      {status}
    </span>
  )
}
