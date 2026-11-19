// Shared by the super admin's zone admin pages and the zone panel.

export const ACCESS_LABEL: Record<string, { text: string; cls: string }> = {
  active: { text: 'Active', cls: 'bg-green-100 text-green-700' },
  grace: { text: 'Grace (read-only)', cls: 'bg-yellow-100 text-yellow-700' },
  expired: { text: 'Expired', cls: 'bg-red-100 text-red-700' },
  blocked: { text: 'Blocked', cls: 'bg-gray-200 text-gray-700' },
  no_subscription: { text: 'No subscription', cls: 'bg-yellow-100 text-yellow-700' },
}

export function fmtDate(d?: string | Date | null) {
  return d ? new Date(d).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—'
}

export function daysLeft(d?: string | Date | null) {
  if (!d) return null
  return Math.ceil((new Date(d).getTime() - Date.now()) / 86_400_000)
}
