import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import PushNotification from '@/models/PushNotification'
import { pointInPolygon, distanceKm } from '@/lib/geo'
import { maxPlausibleKm } from '@/lib/geo-guard'

/**
 * A zone switch needs fixes inside the new zone spanning at least this long
 * (first → latest), at least ZONE_AUTO_MIN_FIXES of them, each a plausible
 * move from the one before. It used to be two fixes 60 s apart, which one
 * spoofed fix and a wait could satisfy.
 */
export const ZONE_AUTO_CONFIRM_MS = 5 * 60_000
export const ZONE_AUTO_MIN_FIXES = 3
/** Fixes closer together than this only refresh nothing (fewer writes). */
const CANDIDATE_STEP_MS = 10_000

// Active zones, cached per process: every location ping of every auto-zone
// driver used to load every polygon.
export const ZONE_CACHE_MS = 60_000
let zoneCache: { at: number; zones: any[] } | null = null
export async function activeZonesCached(): Promise<any[]> {
  const now = Date.now()
  if (zoneCache && now - zoneCache.at < ZONE_CACHE_MS) return zoneCache.zones
  const zones: any[] = await Zone.find({ isActive: true }).select('name polygonPath').lean()
  zoneCache = { at: now, zones }
  return zones
}
/** Test hook: forget the cached zones. */
export function _clearZoneCache() { zoneCache = null }

/**
 * For a driver with zoneAuto on (an ADMIN turns it on — the driver may only
 * turn it off, see PUT /auth/driver/zone): when their position is inside
 * another active zone and no longer inside their own, move them to that zone —
 * once the dwell rule above is met (Driver.zoneAutoCandidate tracks it). Any
 * fix outside the candidate zone, or an implausible jump inside it, restarts
 * it. Logged in zoneHistory and told to the driver through their notification
 * feed. Returns the new zone name when it switched.
 *
 * `known` may carry the driver fields already read by the caller
 * (zoneAuto zoneId zoneName zoneAutoCandidate) to skip a second read.
 */
export async function maybeAutoSwitchZone(driverId: string, lat: number, lng: number, known?: any): Promise<string | null> {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null
  const d: any = known && 'zoneAuto' in known
    ? known
    : await Driver.findById(driverId).select('zoneAuto zoneId zoneName zoneAutoCandidate').lean()
  if (!d?.zoneAuto) return null
  const zones = await activeZonesCached()
  const here = { lat, lng }
  const inside = (z: any) => (z.polygonPath?.length || 0) >= 3 && pointInPolygon(here, z.polygonPath)
  const current = zones.find(z => String(z._id) === String(d.zoneId))
  const target = current && inside(current) ? null : zones.find(z => String(z._id) !== String(d.zoneId) && inside(z))
  const cand = d.zoneAutoCandidate

  if (!target) {
    if (cand?.zoneId) await Driver.updateOne({ _id: driverId }, { $unset: { zoneAutoCandidate: 1 } })
    return null
  }
  const now = new Date()
  const restart = () => Driver.updateOne({ _id: driverId }, {
    $set: { zoneAutoCandidate: { zoneId: String(target._id), firstAt: now, lastAt: now, lastLat: lat, lastLng: lng, fixes: 1 } },
  })
  if (!cand?.zoneId || cand.zoneId !== String(target._id) || !cand.firstAt) {
    await restart()
    return null
  }
  // Plausible movement from the previous fix inside the candidate zone.
  const lastAt = cand.lastAt ? new Date(cand.lastAt).getTime() : new Date(cand.firstAt).getTime()
  if (cand.lastLat != null && cand.lastLng != null) {
    const km = distanceKm({ lat: cand.lastLat, lng: cand.lastLng }, here)
    if (km > maxPlausibleKm(now.getTime() - lastAt)) { await restart(); return null }
  }
  const sinceLast = now.getTime() - lastAt
  const fixes = (Number(cand.fixes) || 1) + (sinceLast >= CANDIDATE_STEP_MS ? 1 : 0)
  const span = now.getTime() - new Date(cand.firstAt).getTime()
  if (span < ZONE_AUTO_CONFIRM_MS || fixes < ZONE_AUTO_MIN_FIXES) {
    if (sinceLast >= CANDIDATE_STEP_MS) {
      await Driver.updateOne(
        { _id: driverId, 'zoneAutoCandidate.zoneId': String(target._id) },
        { $set: { 'zoneAutoCandidate.lastAt': now, 'zoneAutoCandidate.lastLat': lat, 'zoneAutoCandidate.lastLng': lng, 'zoneAutoCandidate.fixes': fixes } },
      )
    }
    return null
  }

  const res = await Driver.updateOne(
    { _id: driverId, zoneAuto: true, zoneId: d.zoneId ?? null, 'zoneAutoCandidate.zoneId': String(target._id) },
    {
      $set: { zoneId: String(target._id), zoneName: target.name },
      $unset: { zoneAutoCandidate: 1 },
      $push: { zoneHistory: { from: d.zoneId || '', fromName: d.zoneName || '', to: String(target._id), toName: target.name, by: 'auto', at: now } },
    },
  )
  if (!res.modifiedCount) return null
  await PushNotification.create({
    title: 'Zone changed', message: `You are now in ${target.name}. Your zone was changed automatically.`,
    target: 'specific', targetUserId: String(driverId), sentAt: now, deliveredCount: 1,
  }).catch(() => {})
  return target.name
}
