// ─────────────────────────────────────────────────────────────────────────────
// Signed fare quotes.
//
// /api/rides/book honours whatever `fare` the client posts whenever it cannot
// recompute one itself, which is every outstation, hire and delivery booking
// and any taxi booking where the zone has no matching pricing row. A patched
// client can book any ride for ₹1.
//
// Rather than duplicate five pricing formulas inside book (and risk the booked
// price drifting from the quoted one), /api/fare/estimate now SIGNS the fare it
// just computed and book verifies that signature. The server therefore only
// ever accepts a price it produced itself, and the rider is charged exactly
// what they were shown.
//
// Rental does not use this — it is priced outright in lib/rental-pricing.ts.
// ─────────────────────────────────────────────────────────────────────────────
import crypto from 'crypto'

const SECRET = process.env.JWT_SECRET || ''
const TTL_MS = 20 * 60 * 1000 // a quote is good for 20 minutes

export type QuotePayload = {
  service: string
  vehicleType: string
  fare: number
  /** Pickup/drop rounded to ~100 m so tiny map jitter doesn't void the quote. */
  cell: string
  /**
   * Every other input that changed the price, signed with it: tripType, hire
   * hours (+ the per-hour rate), outstation stops / days / night-halt /
   * empty-return, in-city stops, delivery weight. /rides/book rejects a token
   * whose signed values differ from the booking (see quoteExtras).
   */
  x?: Record<string, string | number>
  exp: number
}

/** Stops rounded like the pickup/drop cell, as one comparable string. */
export function stopsKey(stops: any): string {
  if (!Array.isArray(stops)) return ''
  return stops
    .filter((s: any) => s && s.lat != null && s.lng != null && Number.isFinite(+s.lat) && Number.isFinite(+s.lng))
    .map((s: any) => cellOf(+s.lat, +s.lng))
    .join(';')
}

/** Delivery weight as signed (0.1 kg). */
export function weightKey(w: any): number {
  const n = Number(w)
  return Number.isFinite(n) && n > 0 ? Math.round(n * 10) / 10 : 0
}

/** Hire hours exactly as /fare/estimate bills them. */
export function hireHours(h: any): number {
  return Math.max(1, Math.ceil(Number(h) || 0))
}

function cellOf(lat?: number | null, lng?: number | null): string {
  if (lat == null || lng == null) return 'x'
  return `${Math.round(lat * 1000)}:${Math.round(lng * 1000)}`
}

export function quoteCell(
  pickupLat?: number | null, pickupLng?: number | null,
  dropLat?: number | null, dropLng?: number | null,
): string {
  return `${cellOf(pickupLat, pickupLng)}|${cellOf(dropLat, dropLng)}`
}

function sign(body: string): string {
  return crypto.createHmac('sha256', SECRET).update(body).digest('base64url')
}

/** Returns an opaque token the client passes back at booking time. */
export function signQuote(p: Omit<QuotePayload, 'exp'>): string {
  if (!SECRET) return ''
  const payload: QuotePayload = { ...p, exp: Date.now() + TTL_MS }
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${body}.${sign(body)}`
}

export type QuoteCheck =
  | { ok: true; fare: number; x: Record<string, string | number> }
  | { ok: false; reason: string }

/**
 * Verifies a token really came from us, has not expired, and matches the ride
 * being booked. Signature comparison is constant-time.
 */
export function verifyQuote(
  token: string | undefined | null,
  expect: { service: string; vehicleType: string; cell: string; x?: Record<string, string | number> },
): QuoteCheck {
  if (!SECRET) return { ok: false, reason: 'Server not configured' }
  if (!token || typeof token !== 'string' || !token.includes('.')) {
    return { ok: false, reason: 'Missing quote' }
  }
  const [body, mac] = token.split('.')
  const expected = sign(body)
  const a = Buffer.from(mac || '')
  const b = Buffer.from(expected)
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { ok: false, reason: 'Quote signature invalid' }
  }

  let p: QuotePayload
  try {
    p = JSON.parse(Buffer.from(body, 'base64url').toString())
  } catch {
    return { ok: false, reason: 'Quote malformed' }
  }

  if (!p.exp || p.exp < Date.now()) return { ok: false, reason: 'Quote expired' }
  if (p.service !== expect.service) return { ok: false, reason: 'Quote service mismatch' }
  if (p.vehicleType !== expect.vehicleType) return { ok: false, reason: 'Quote vehicle mismatch' }
  if (p.cell !== expect.cell) return { ok: false, reason: 'Quote route mismatch' }
  if (!Number.isFinite(p.fare) || p.fare < 0) return { ok: false, reason: 'Quote fare invalid' }
  // Each value the caller expects must equal the signed one (missing = '').
  const signed = p.x || {}
  for (const [k, v] of Object.entries(expect.x || {})) {
    if (String(signed[k] ?? '') !== String(v ?? '')) return { ok: false, reason: `Quote ${k} mismatch` }
  }

  return { ok: true, fare: p.fare, x: signed }
}

/**
 * Enforcement is opt-in so already-installed app builds (which do not send a
 * token yet) keep working during rollout. Set ENFORCE_QUOTE_TOKEN=1 once the
 * updated apps are live to reject unsigned fares outright.
 */
export const ENFORCE_QUOTES = process.env.ENFORCE_QUOTE_TOKEN === '1'
