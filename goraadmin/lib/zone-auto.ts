import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import PushNotification from '@/models/PushNotification'
import { pointInPolygon } from '@/lib/geo'

/** A zone switch needs two fixes inside the new zone at least this far apart. */
export const ZONE_AUTO_CONFIRM_MS = 60_000

/**
 * For a driver with zoneAuto on: when their position is inside another active
 * zone and no longer inside their own, move them to that zone — but only once
 * a SECOND fix, at least ZONE_AUTO_CONFIRM_MS after the first, is still inside
 * it (Driver.zoneAutoCandidate holds the first). One stray or spoofed fix can
 * no longer move a driver into another city's pool. Any fix outside the
 * candidate zone resets it. Logged in zoneHistory and told to the driver
 * through their notification feed. Returns the new zone name when it switched.
 */
export async function maybeAutoSwitchZone(driverId: string, lat: number, lng: number): Promise<string | null> {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null
  const d: any = await Driver.findById(driverId).select('zoneAuto zoneId zoneName zoneAutoCandidate').lean()
  if (!d?.zoneAuto) return null
  const zones: any[] = await Zone.find({ isActive: true }).select('name polygonPath').lean()
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
  if (!cand?.zoneId || cand.zoneId !== String(target._id) || !cand.firstAt) {
    await Driver.updateOne({ _id: driverId }, { $set: { zoneAutoCandidate: { zoneId: String(target._id), firstAt: now } } })
    return null
  }
  if (now.getTime() - new Date(cand.firstAt).getTime() < ZONE_AUTO_CONFIRM_MS) return null

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
