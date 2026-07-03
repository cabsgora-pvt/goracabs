export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/driver/summary → today's + week's earnings, rides, distance
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const now = new Date()
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const weekStart = new Date(todayStart)
    weekStart.setDate(weekStart.getDate() - 6) // last 7 days (incl today)

    const rides = await Ride.find({
      driverId: payload.id, status: 'completed',
      completedAt: { $gte: weekStart },
    }).select('driverEarning distance completedAt').lean() as any[]

    let today = 0, week = 0, todayRides = 0, todayDistance = 0
    for (const r of rides) {
      const earn = r.driverEarning || 0
      week += earn
      if (r.completedAt && new Date(r.completedAt) >= todayStart) {
        today += earn
        todayRides += 1
        todayDistance += r.distance || 0
      }
    }

    const driver: any = await Driver.findById(payload.id).select('totalRides totalEarnings').lean()

    return withCors({
      today: Math.round(today),
      week: Math.round(week),
      todayRides,
      todayDistance: Math.round(todayDistance),
      totalRides: driver?.totalRides || 0,
      totalEarnings: Math.round(driver?.totalEarnings || 0),
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
