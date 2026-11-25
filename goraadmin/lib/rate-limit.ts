import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import RateLimit from '@/models/RateLimit'

// Two limiters:
//   • rateLimit()       — sync, in-memory sliding window, per process. Kept for
//                         existing callers; resets on restart.
//   • limitHit() / rateLimitAsync() / limitPeek() / limitReset()
//                       — Mongo-backed fixed windows (atomic $inc on one doc
//                         per window, TTL-expired), so counts and lockouts
//                         survive a restart and are shared by every process.
//                         A small in-memory cache remembers windows already
//                         over the limit, so a flood is refused without a DB
//                         round trip. Fails open if Mongo is unreachable.

const hits = new Map<string, number[]>()

// The LAST X-Forwarded-For entry is the one our nginx appended (the real peer);
// earlier entries are whatever the client sent and are trivially spoofed.
export function clientIp(req: NextRequest): string {
  const fwd = req.headers.get('x-forwarded-for')
  if (fwd) {
    const parts = fwd.split(',').map(s => s.trim()).filter(Boolean)
    if (parts.length) return parts[parts.length - 1]
  }
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

// ── Mongo-backed ─────────────────────────────────────────────────────────────

/** Windows known (to this process) to be over their limit: docId -> window end. */
const blocked = new Map<string, number>()

export function windowId(key: string, windowMs: number, now = Date.now()) {
  const n = Math.floor(now / windowMs)
  return { id: `${key}:${n}`, endsAt: (n + 1) * windowMs }
}

/** Test hook / restart simulation: forget the in-memory fast path. */
export function _clearRateLimitMemory() { blocked.clear(); hits.clear() }

/** Count one hit on `key`; true while the window's count is <= limit. */
export async function limitHit(key: string, limit: number, windowMs: number): Promise<boolean> {
  const { id, endsAt } = windowId(key, windowMs)
  const now = Date.now()
  const b = blocked.get(id)
  if (b && b > now) return false
  try {
    await connectDB()
    const doc: any = await RateLimit.findOneAndUpdate(
      { _id: id },
      { $inc: { count: 1 }, $setOnInsert: { expiresAt: new Date(endsAt) } },
      { upsert: true, new: true },
    ).lean()
    const ok = Number(doc?.count || 0) <= limit
    if (!ok) {
      blocked.set(id, endsAt)
      if (blocked.size > 5000) for (const [k, v] of blocked) if (v <= now) blocked.delete(k)
    }
    return ok
  } catch {
    return true
  }
}

/** Current count of `key` in this window, without counting a hit. */
export async function limitPeek(key: string, windowMs: number): Promise<number> {
  const { id } = windowId(key, windowMs)
  try {
    await connectDB()
    const doc: any = await RateLimit.findById(id).lean()
    return Number(doc?.count || 0)
  } catch { return 0 }
}

/** Clear `key`'s current window (e.g. a successful login clears its failures). */
export async function limitReset(key: string, windowMs: number) {
  const { id } = windowId(key, windowMs)
  blocked.delete(id)
  try { await connectDB(); await RateLimit.deleteOne({ _id: id }) } catch { /* ignore */ }
}

/** Mongo-backed version of rateLimit(): `key` + caller IP. */
export async function rateLimitAsync(req: NextRequest, key: string, limit: number, windowMs: number): Promise<boolean> {
  return limitHit(`${key}:${clientIp(req)}`, limit, windowMs)
}
