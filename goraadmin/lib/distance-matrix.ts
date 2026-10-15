// ─────────────────────────────────────────────────────────────────────────────
// Optional traffic-aware refinement for the top-K pickup candidates.
//
// Why not just call Directions per driver? Because that is one billed request
// per driver per estimate. Distance Matrix takes up to 25 origins against one
// destination in a SINGLE request, and we cache on the (originCell, destCell,
// 5-minute bucket) key so a busy pickup point collapses to ~1 call per 5 min.
//
// This is strictly an enhancement: every failure path returns null and the
// caller keeps the lib/eta.ts model estimate.
// ─────────────────────────────────────────────────────────────────────────────
import { getSettings } from './settings'
import { geoCell } from './eta'
import type { LatLng } from './geo'

const MAX_ORIGINS_PER_CALL = 25
const CACHE_TTL_MS = 5 * 60 * 1000
const TIME_BUCKET_MS = 5 * 60 * 1000

export type MatrixLeg = { km: number; min: number }

type CacheEntry = { value: MatrixLeg; expiresAt: number }
const cache = new Map<string, CacheEntry>()

// The DESTINATION (a pickup point) is bucketed coarsely — that is where the
// cache wins, since many riders request from the same mall/station.
//
// The ORIGIN (a driver) must be bucketed finely. Using the ~800 m geoCell here
// made two distinct drivers in the same cell share one cached leg, so the whole
// point of refining a shortlist — telling close candidates apart — was lost.
// ~110 m keeps them distinct while still absorbing GPS jitter.
const ORIGIN_PRECISION = 1000 // 3 decimal places ≈ 110 m

function originKey(o: LatLng): string {
  return `${Math.round(o.lat * ORIGIN_PRECISION)}:${Math.round(o.lng * ORIGIN_PRECISION)}`
}

function cacheKey(origin: LatLng, dest: LatLng, now: number): string {
  const bucket = Math.floor(now / TIME_BUCKET_MS)
  return `${originKey(origin)}|${geoCell(dest.lat, dest.lng)}|${bucket}`
}

function readCache(key: string, now: number): MatrixLeg | null {
  const hit = cache.get(key)
  if (!hit) return null
  if (hit.expiresAt <= now) { cache.delete(key); return null }
  return hit.value
}

const CACHE_MAX = 5000
const CACHE_TARGET = 4000

function writeCache(key: string, value: MatrixLeg, now: number) {
  cache.set(key, { value, expiresAt: now + CACHE_TTL_MS })
  if (cache.size <= CACHE_MAX) return

  // Sweep expired entries first.
  for (const [k, v] of cache) {
    if (v.expiresAt <= now) cache.delete(k)
    if (cache.size <= CACHE_TARGET) return
  }
  // Still over budget means everything is live, so evict oldest-first. Map
  // iterates in insertion order. The previous version only deleted expired
  // entries, so a fully-live cache stayed pinned above the limit and re-walked
  // the whole map on every insert.
  for (const k of cache.keys()) {
    cache.delete(k)
    if (cache.size <= CACHE_TARGET) return
  }
}

function apiKey(): string {
  try {
    const s: any = getSettings()
    return s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
  } catch {
    return ''
  }
}

/**
 * Traffic-aware km + minutes from each origin to one destination.
 *
 * Returns an array parallel to `origins`; entries are null where Google had no
 * route or the call failed. Returns all-null (without calling out) when no
 * Maps key is configured, so local/dev environments degrade silently.
 */
export async function matrixToDestination(
  origins: LatLng[],
  dest: LatLng,
): Promise<Array<MatrixLeg | null>> {
  const now = Date.now()
  const result: Array<MatrixLeg | null> = new Array(origins.length).fill(null)
  if (!origins.length) return result

  // Serve what we can from cache; collect the rest.
  const pending: Array<{ idx: number; origin: LatLng; key: string }> = []
  origins.forEach((o, idx) => {
    const key = cacheKey(o, dest, now)
    const hit = readCache(key, now)
    if (hit) result[idx] = hit
    else pending.push({ idx, origin: o, key })
  })
  if (!pending.length) return result

  const key = apiKey()
  if (!key) return result

  for (let i = 0; i < pending.length; i += MAX_ORIGINS_PER_CALL) {
    const batch = pending.slice(i, i + MAX_ORIGINS_PER_CALL)
    const originParam = batch.map(b => `${b.origin.lat},${b.origin.lng}`).join('|')
    const url =
      `https://maps.googleapis.com/maps/api/distancematrix/json` +
      `?origins=${encodeURIComponent(originParam)}` +
      `&destinations=${encodeURIComponent(`${dest.lat},${dest.lng}`)}` +
      `&mode=driving&departure_time=now&traffic_model=best_guess` +
      `&key=${key}`
    try {
      const r = await fetch(url)
      const data = await r.json()
      if (data.status !== 'OK' || !Array.isArray(data.rows)) {
        console.error('[DistanceMatrix]', data.status, data.error_message)
        continue
      }
      data.rows.forEach((row: any, n: number) => {
        const el = row?.elements?.[0]
        const target = batch[n]
        if (!el || el.status !== 'OK' || !target) return
        const leg: MatrixLeg = {
          km: +((el.distance?.value || 0) / 1000).toFixed(2),
          min: Math.round(((el.duration_in_traffic?.value ?? el.duration?.value) || 0) / 60),
        }
        result[target.idx] = leg
        writeCache(target.key, leg, now)
      })
    } catch (e) {
      console.error('[DistanceMatrix] request failed', e)
    }
  }

  return result
}
