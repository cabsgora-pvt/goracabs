// Indian mobile numbers are stored as exactly 10 digits. Accepts "+91 98765 43210",
// "919876543210", "09876543210" or "9876543210"; anything else is rejected (null),
// so "9876543210" and "+919876543210" can never become two accounts.
export function normalizePhone(input: unknown): string | null {
  if (input === null || input === undefined) return null
  if (typeof input !== 'string' && typeof input !== 'number') return null
  let p = String(input).replace(/\D/g, '')
  if (p.length === 12 && p.startsWith('91')) p = p.slice(2)
  else if (p.length === 11 && p.startsWith('0')) p = p.slice(1)
  return /^[6-9]\d{9}$/.test(p) ? p : null
}
