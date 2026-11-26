export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import mongoose from 'mongoose'

export async function OPTIONS() { return corsOptions() }

const DAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
function fmtDur(mins: number) {
  if (mins <= 0) return '—'
  const h = Math.floor(mins / 60), m = Math.round(mins % 60)
  return h > 0 ? `${h}h ${m}m` : `${m}m`
}


// ── Additive (driver app 1.5.1): IST day buckets with the money split ──
// Every completed ride counts on the IST day of its completedAt. Per bucket:
// earning (driverEarning), what came from cash vs online/wallet rides, the
// commission Gora took (commissionAmount) and tips.
const IST_MS = 5.5 * 60 * 60 * 1000
type Bucket = { earning: number; rides: number; cash: number; online: number; commission: number; tips: number; distanceKm: number; durationMin: number }
const emptyBucket = (): Bucket => ({ earning: 0, rides: 0, cash: 0, online: 0, commission: 0, tips: 0, distanceKm: 0, durationMin: 0 })
function addInto(a: Bucket, b: Bucket) {
  for (const k of Object.keys(a) as (keyof Bucket)[]) a[k] += b[k]
}
const rounded = (b: Bucket): Bucket => ({
  earning: Math.round(b.earning), rides: b.rides, cash: Math.round(b.cash), online: Math.round(b.online),
  commission: Math.round(b.commission), tips: Math.round(b.tips),
  distanceKm: Math.round(b.distanceKm * 10) / 10, durationMin: Math.round(b.durationMin),
})
/** 'YYYY-MM-DD' of the IST day `days` before `now`'s IST day. */
function istDay(now: Date, days = 0): string {
  const ist = new Date(now.getTime() + IST_MS)
  ist.setUTCDate(ist.getUTCDate() - days)
  return ist.toISOString().slice(0, 10)
}

async function istBreakdown(driverId: string, now: Date) {
  const ist = new Date(now.getTime() + IST_MS)
  const yearStartIst = Date.UTC(ist.getUTCFullYear(), 0, 1)
  const weekStartIst = Date.parse(istDay(now, 6) + 'T00:00:00Z')
  const from = new Date(Math.min(yearStartIst, weekStartIst) - IST_MS)
  const rows: any[] = await Ride.aggregate([
    { $match: { driverId: new mongoose.Types.ObjectId(driverId), status: 'completed', completedAt: { $gte: from } } },
    { $group: {
      _id: { $dateToString: { format: '%Y-%m-%d', date: '$completedAt', timezone: '+05:30' } },
      earning: { $sum: { $ifNull: ['$driverEarning', 0] } },
      rides: { $sum: 1 },
      cash: { $sum: { $cond: [{ $eq: ['$paymentMode', 'cash'] }, { $ifNull: ['$driverEarning', 0] }, 0] } },
      online: { $sum: { $cond: [{ $ne: ['$paymentMode', 'cash'] }, { $ifNull: ['$driverEarning', 0] }, 0] } },
      commission: { $sum: { $ifNull: ['$commissionAmount', 0] } },
      tips: { $sum: { $ifNull: ['$tip', 0] } },
      distanceKm: { $sum: { $ifNull: ['$distance', 0] } },
      durationMin: { $sum: { $ifNull: ['$duration', 0] } },
    } },
  ])
  const byDay = new Map<string, Bucket>()
  for (const r of rows) {
    const { _id, ...b } = r
    byDay.set(String(_id), { ...emptyBucket(), ...b })
  }
  const days = []
  for (let i = 6; i >= 0; i--) {
    const d = istDay(now, i)
    days.push({ date: d, ...rounded(byDay.get(d) || emptyBucket()) })
  }
  const year = ist.getUTCFullYear()
  const months = []
  for (let m = 1; m <= ist.getUTCMonth() + 1; m++) {
    const prefix = `${year}-${String(m).padStart(2, '0')}-`
    const b = emptyBucket()
    byDay.forEach((v, k) => { if (k.startsWith(prefix)) addInto(b, v) })
    months.push({ month: m, year, ...rounded(b) })
  }
  const today = rounded(byDay.get(istDay(now)) || emptyBucket())
  const week = emptyBucket()
  for (let i = 0; i < 7; i++) addInto(week, byDay.get(istDay(now, i)) || emptyBucket())
  return { timezone: 'Asia/Kolkata', today, week: rounded(week), month: months[months.length - 1], days, months }
}

// GET /api/rides/driver/earnings?date=YYYY-MM-DD
// Returns the 7-day daily breakdown ending at `date` (default today) + overall summary.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const now = new Date()
    const dateParam = req.nextUrl.searchParams.get('date')
    const end = dateParam ? new Date(dateParam) : now
    const endDay = new Date(end.getFullYear(), end.getMonth(), end.getDate())
    const windowStart = new Date(endDay); windowStart.setDate(windowStart.getDate() - 6)
    const windowEnd = new Date(endDay); windowEnd.setDate(windowEnd.getDate() + 1) // exclusive

    const windowRides = await Ride.find({
      driverId: payload.id, status: 'completed',
      completedAt: { $gte: windowStart, $lt: windowEnd },
    }).select('driverEarning distance duration completedAt').lean() as any[]

    // 7 day buckets (oldest → newest)
    const daily: any[] = []
    for (let i = 0; i < 7; i++) {
      const dStart = new Date(windowStart); dStart.setDate(dStart.getDate() + i)
      const dEnd = new Date(dStart); dEnd.setDate(dEnd.getDate() + 1)
      let amt = 0, rides = 0, dist = 0, dur = 0
      for (const r of windowRides) {
        const t = new Date(r.completedAt)
        if (t >= dStart && t < dEnd) { amt += r.driverEarning || 0; rides++; dist += r.distance || 0; dur += r.duration || 0 }
      }
      daily.push({
        date: DAY[dStart.getDay()],
        amount: String(Math.round(amt)),
        rides: String(rides),
        distance: `${Math.round(dist)} km`,
        duration: fmtDur(dur),
      })
    }

    // Overall summary — always current (independent of the picked window)
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const weekStart = new Date(todayStart); weekStart.setDate(weekStart.getDate() - 6)
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)
    const earliest = new Date(Math.min(monthStart.getTime(), weekStart.getTime()))
    const recent = await Ride.find({
      driverId: payload.id, status: 'completed', completedAt: { $gte: earliest },
    }).select('driverEarning completedAt').lean() as any[]
    let today = 0, week = 0, month = 0
    for (const r of recent) {
      const t = new Date(r.completedAt); const e = r.driverEarning || 0
      if (t >= todayStart) today += e
      if (t >= weekStart) week += e
      if (t >= monthStart) month += e
    }
    const driver: any = await Driver.findById(payload.id).select('totalRides').lean()

    // Additive: IST buckets with cash / online / commission / tips.
    let breakdown: any = null
    try { breakdown = await istBreakdown(String(payload.id), now) } catch (e) { console.error('[earnings] breakdown failed', e) }

    return withCors({
      ...(breakdown ? { breakdown } : {}),
      daily,
      summary: {
        today: `₹ ${Math.round(today)}`,
        week: `₹ ${Math.round(week)}`,
        month: `₹ ${Math.round(month)}`,
        totalRides: String(driver?.totalRides || 0),
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
