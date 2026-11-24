import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import PushNotification from '@/models/PushNotification'
import { pointInPolygon } from '@/lib/geo'

/**
 * For a driver with zoneAuto on: when their position is inside another active
 * zone and no longer inside their own, move them to that zone. Logged in
 * zoneHistory and told to the driver through their notification feed.
 * Returns the new zone name when it switched.
 */
export async function maybeAutoSwitchZone(driverId: string, lat: number, lng: number): Promise<string | null> {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null
  const d: any = await Driver.findById(driverId).select('zoneAuto zoneId zoneName').lean()
  if (!d?.zoneAuto) return null
  const zones: any[] = await Zone.find({ isActive: true }).select('name polygonPath').lean()
  const here = { lat, lng }
  const inside = (z: any) => (z.polygonPath?.length || 0) >= 3 && pointInPolygon(here, z.polygonPath)
  const current = zones.find(z => String(z._id) === String(d.zoneId))
  if (current && inside(current)) return null
  const target = zones.find(z => String(z._id) !== String(d.zoneId) && inside(z))
  if (!target) return null
  const res = await Driver.updateOne(
    { _id: driverId, zoneAuto: true, zoneId: d.zoneId ?? null },
    {
      $set: { zoneId: String(target._id), zoneName: target.name },
      $push: { zoneHistory: { from: d.zoneId || '', fromName: d.zoneName || '', to: String(target._id), toName: target.name, by: 'auto', at: new Date() } },
    },
  )
  if (!res.modifiedCount) return null
  await PushNotification.create({
    title: 'Zone changed', message: `You are now in ${target.name}. Your zone was changed automatically.`,
    target: 'specific', targetUserId: String(driverId), sentAt: new Date(), deliveredCount: 1,
  }).catch(() => {})
  return target.name
}
