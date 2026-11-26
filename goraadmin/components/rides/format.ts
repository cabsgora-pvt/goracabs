// Small display helpers shared by the rides pages. All times shown in IST.
export const fmtIST = (d?: any, withSeconds = false) => {
  if (!d) return '—'
  const t = new Date(d)
  if (isNaN(t.getTime())) return '—'
  return t.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', ...(withSeconds ? { second: '2-digit' } : {}) })
}
export const fmtISTShort = (d?: any) => {
  if (!d) return '—'
  const t = new Date(d)
  if (isNaN(t.getTime())) return '—'
  return t.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}
export const rupees = (n: any) => `₹${Math.round((Number(n) || 0) * 100) / 100}`
export const label = (s?: string) => (s || '').replace(/_/g, ' ')
/** "1 h 05 m" / "12 m" between two times (to defaults to now). */
export const elapsed = (from?: any, to: any = Date.now()) => {
  if (!from) return '—'
  const ms = new Date(to).getTime() - new Date(from).getTime()
  if (!(ms >= 0)) return '—'
  const m = Math.floor(ms / 60000)
  return m >= 60 ? `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} m` : `${m} m`
}
export const rideHref = (id: any) => `/rides/${String(id)}`
