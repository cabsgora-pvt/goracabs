import { distanceKm } from './geo'

/** Driver location plausibility (auth/driver/location, /online). */
export const GEO_GUARD = {
  /** Faster than this between two fixes is treated as a GPS jump / spoof. */
  MAX_KMPH: 200,
  /** Moves shorter than this are never called a jump (GPS jitter on quick pings). */
  MIN_JUMP_KM: 1,
}

/** True when moving from the driver's stored fix to (lat,lng) now is impossible. */
export function isTeleport(prev: any, lat: number, lng: number, now: number = Date.now()): boolean {
  if (!prev || prev.currentLat == null || prev.currentLng == null || !prev.locationUpdatedAt) return false
  if (prev.currentLat === 0 && prev.currentLng === 0) return false
  const km = distanceKm({ lat: prev.currentLat, lng: prev.currentLng }, { lat, lng })
  if (km <= GEO_GUARD.MIN_JUMP_KM) return false
  const hours = Math.max(1 / 3600, (now - new Date(prev.locationUpdatedAt).getTime()) / 3_600_000)
  return km / hours > GEO_GUARD.MAX_KMPH
}
