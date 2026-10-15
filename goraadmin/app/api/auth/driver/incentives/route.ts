export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import IncentiveRule from '@/models/IncentiveRule'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { istParts } from '@/lib/eta'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000

/** Start of the current day/week/month in IST, returned as a UTC Date. */
function periodStart(period: string, now = new Date()): Date {
  const ist = new Date(now.getTime() + IST_OFFSET_MS)
  const y = ist.getUTCFullYear(), m = ist.getUTCMonth(), d = ist.getUTCDate()
  let startIst: Date
  if (period === 'month') {
    startIst = new Date(Date.UTC(y, m, 1))
  } else if (period === 'week') {
    // Week runs Monday→Sunday.
    const dow = (ist.getUTCDay() + 6) % 7
    startIst = new Date(Date.UTC(y, m, d - dow))
  } else {
    startIst = new Date(Date.UTC(y, m, d))
  }
  return new Date(startIst.getTime() - IST_OFFSET_MS)
}

/** End of the period, for the deadline label. */
function periodEnd(period: string, now = new Date()): Date {
  const start = periodStart(period, now)
  const days = period === 'month' ? 31 : period === 'week' ? 7 : 1
  if (period === 'month') {
    const ist = new Date(start.getTime() + IST_OFFSET_MS)
    const nextMonth = new Date(Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth() + 1, 1))
    return new Date(nextMonth.getTime() - IST_OFFSET_MS)
  }
  return new Date(start.getTime() + days * 24 * 60 * 60 * 1000)
}

// GET → every active incentive with THIS driver's real progress.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const driverId = String((payload as any).id)

    await connectDB()
    const driver: any = await Driver.findById(driverId).select('selectedVehicleTypeName zoneId').lean()
    const now = new Date()

    const rules: any[] = await IncentiveRule.find({
      isActive: true,
      $and: [
        { $or: [{ validFrom: null }, { validFrom: { $exists: false } }, { validFrom: { $lte: now } }] },
        { $or: [{ validTo: null }, { validTo: { $exists: false } }, { validTo: { $gte: now } }] },
      ],
    }).sort({ createdAt: 1 }).lean()

    if (!rules.length) return withCors({ incentives: [] })

    // One ride fetch covers every rule — the longest window we might need.
    const widest = rules.some(r => r.period === 'month') ? 'month'
      : rules.some(r => r.period === 'week') ? 'week' : 'day'
    const rides: any[] = await Ride.find({
      driverId,
      status: 'completed',
      completedAt: { $gte: periodStart(widest, now) },
    }).select('completedAt service vehicleType zoneId driverEarning').lean()

    const incentives = rules
      .filter(r => {
        // Rules narrowed to a vehicle/zone the driver is not on simply do not apply.
        if (r.vehicleTypeName && driver?.selectedVehicleTypeName !== r.vehicleTypeName) return false
        if (r.zoneId && String(driver?.zoneId || '') !== String(r.zoneId)) return false
        return true
      })
      .map(r => {
        const from = periodStart(r.period || 'day', now)
        const windowed = rides.filter(ride => {
          if (!ride.completedAt || new Date(ride.completedAt) < from) return false
          if (r.service && ride.service !== r.service) return false
          if (r.vehicleTypeName && ride.vehicleType !== r.vehicleTypeName) return false
          if (r.zoneId && String(ride.zoneId || '') !== String(r.zoneId)) return false
          // Hour window (IST). start == end means all day.
          if ((r.startHour || 0) !== (r.endHour || 0)) {
            const h = istParts(new Date(ride.completedAt)).hour
            const s = r.startHour || 0, e = r.endHour || 0
            const inWindow = s < e ? (h >= s && h < e) : (h >= s || h < e) // handles overnight
            if (!inWindow) return false
          }
          return true
        })

        const current = r.metric === 'earnings'
          ? Math.round(windowed.reduce((sum, x) => sum + (x.driverEarning || 0), 0))
          : windowed.length
        const target = r.target || 0
        const progress = target > 0 ? Math.min(1, current / target) : 0

        return {
          id: String(r._id),
          title: r.title || '',
          description: r.description || '',
          metric: r.metric || 'rides',
          target,
          current,
          progress: +progress.toFixed(3),
          achieved: target > 0 && current >= target,
          reward: r.rewardAmount || 0,
          period: r.period || 'day',
          endsAt: periodEnd(r.period || 'day', now).toISOString(),
        }
      })

    return withCors({ incentives })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
