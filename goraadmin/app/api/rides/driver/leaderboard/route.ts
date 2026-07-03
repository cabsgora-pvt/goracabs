export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET /api/rides/driver/leaderboard → top drivers in the SAME zone, ranked by rides.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()

    const me: any = await Driver.findById(payload.id).select('zoneId zoneName').lean()
    if (!me) return withCors({ error: 'Driver not found' }, 404)

    const query: any = { status: 'approved' }
    if (me.zoneId) query.zoneId = me.zoneId

    const drivers = await Driver.find(query)
      .select('name totalRides totalEarnings')
      .sort({ totalRides: -1, totalEarnings: -1 })
      .limit(50).lean() as any[]

    const entries = drivers.map((d, i) => ({
      rank: i + 1,
      name: d.name || 'Driver',
      rides: d.totalRides || 0,
      earnings: Math.round(d.totalEarnings || 0),
      isMe: String(d._id) === String(payload.id),
    }))

    return withCors({ zone: me.zoneName || 'Your Zone', entries })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
