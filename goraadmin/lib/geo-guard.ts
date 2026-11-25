import { distanceKm } from './geo'

/** Driver location plausibility (auth/driver/location, /online). */
export const GEO_GUARD = {
  /** Faster than this between two fixes is treated as a GPS jump / spoof. */
  MAX_KMPH: 200,
  /**
   * GPS jitter allowed on top of the speed budget for every move. It used to be
   * a 1 km grace inside which no speed check ran at all, so a spoofer could
   * walk the driver anywhere in 1 km steps a second apart.
   */
  JITTER_KM: 0.05,
  /** The speed budget never uses less elapsed time than this (quick pings). */
  MIN_ELAPSED_SEC: 3,
  /** At most one stored fix per driver per this many ms (extra pings are dropped). */
  STORE_EVERY_MS: 3_000,
}

/** Furthest a driver can plausibly have moved in `elapsedMs`. */
export function maxPlausibleKm(elapsedMs: number): number {
  const hours = Math.max(GEO_GUARD.MIN_ELAPSED_SEC / 3600, Math.max(0, elapsedMs) / 3_600_000)
  return GEO_GUARD.JITTER_KM + GEO_GUARD.MAX_KMPH * hours
}

/** True when moving from the driver's stored fix to (lat,lng) now is impossible. */
export function isTeleport(prev: any, lat: number, lng: number, now: number = Date.now()): boolean {
  if (!prev || prev.currentLat == null || prev.currentLng == null || !prev.locationUpdatedAt) return false
  if (prev.currentLat === 0 && prev.currentLng === 0) return false
  const km = distanceKm({ lat: prev.currentLat, lng: prev.currentLng }, { lat, lng })
  return km > maxPlausibleKm(now - new Date(prev.locationUpdatedAt).getTime())
}

/** True when the driver's last stored fix is too recent to store another one. */
export function tooSoonToStore(prev: any, now: number = Date.now()): boolean {
  if (!prev?.locationUpdatedAt) return false
  const age = now - new Date(prev.locationUpdatedAt).getTime()
  return age >= 0 && age < GEO_GUARD.STORE_EVERY_MS
}
