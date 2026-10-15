// In-memory, per-process sliding-window limiter for public routes that call a
// paid Google API (Directions) with no auth gate. Good enough for a single-VPS
// deployment; would need a shared store (Redis) behind a load balancer.
import { NextRequest } from 'next/server'

const hits = new Map<string, number[]>()

function clientIp(req: NextRequest): string {
  const fwd = req.headers.get('x-forwarded-for')
  if (fwd) return fwd.split(',')[0].trim()
  return req.headers.get('x-real-ip') || 'unknown'
}

/** Returns true if `key` (route name) + caller IP is still within the limit. */
export function rateLimit(req: NextRequest, key: string, limit: number, windowMs: number): boolean {
  const id = `${key}:${clientIp(req)}`
  const now = Date.now()
  const windowStart = now - windowMs
  const recent = (hits.get(id) || []).filter(t => t > windowStart)
  if (recent.length >= limit) {
    hits.set(id, recent)
    return false
  }
  recent.push(now)
  hits.set(id, recent)
  // Opportunistic cleanup so the map doesn't grow unbounded.
  if (hits.size > 5000) {
    for (const [k, v] of hits) {
      if (!v.some(t => t > windowStart)) hits.delete(k)
    }
  }
  return true
}
