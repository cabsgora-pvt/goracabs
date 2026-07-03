export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

const DAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
function fmtDur(mins: number) {
  if (mins <= 0) return '—'
  const h = Math.floor(mins / 60), m = Math.round(mins % 60)
  return h > 0 ? `${h}h ${m}m` : `${m}m`
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

    return withCors({
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
