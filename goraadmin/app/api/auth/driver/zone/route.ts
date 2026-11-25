export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Zone from '@/models/Zone'
import AccountRequest from '@/models/AccountRequest'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { publicRequest } from '@/lib/account-requests'

export async function OPTIONS() { return corsOptions() }

// GET → { zoneId, zoneName, zoneAuto, zones: [{id,name}], pendingRequest, history }
// PUT { zoneAuto: false } → stop following my location. { zoneAuto: true } → 403
//     ZONE_AUTO_ADMIN_ONLY (only an admin turns it on).
export async function GET(req: NextRequest) {
  const p: any = requireDriverAuth(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  await connectDB()
  const [d, zones, pending]: any[] = await Promise.all([
    Driver.findById(p.id).select('zoneId zoneName zoneAuto zoneHistory').lean(),
    Zone.find({ isActive: true }).select('name').sort({ name: 1 }).lean(),
    AccountRequest.findOne({ userType: 'driver', userId: p.id, kind: 'zone_change', status: 'pending' }).sort({ createdAt: -1 }).lean(),
  ])
  if (!d) return withCors({ error: 'Driver not found' }, 404)
  return withCors({
    zoneId: d.zoneId || '', zoneName: d.zoneName || '', zoneAuto: !!d.zoneAuto,
    zones: zones.map((z: any) => ({ id: String(z._id), name: z.name })),
    pendingRequest: pending ? publicRequest(pending) : null,
    history: (d.zoneHistory || []).slice(-10).reverse(),
  })
}

export async function PUT(req: NextRequest) {
  const p: any = requireDriverAuth(req); if (!p) return withCors({ error: 'Unauthorized' }, 401)
  const b = await req.json().catch(() => ({}))
  if (typeof b.zoneAuto !== 'boolean') return withCors({ error: 'zoneAuto must be true or false' }, 400)
  // Only an admin may turn automatic zone ON (drivers/{id} PUT zoneAuto) — a
  // driver following their own GPS could otherwise hop into another city's
  // pool. The driver may still turn it OFF.
  if (b.zoneAuto === true) {
    return withCors({ error: 'Automatic zone can only be turned on by support. Ask for a zone change instead.', code: 'ZONE_AUTO_ADMIN_ONLY' }, 403)
  }
  await connectDB()
  const d: any = await Driver.findByIdAndUpdate(p.id, { $set: { zoneAuto: false }, $unset: { zoneAutoCandidate: 1 } }, { new: true }).select('zoneAuto').lean()
  if (!d) return withCors({ error: 'Driver not found' }, 404)
  return withCors({ success: true, zoneAuto: !!d.zoneAuto })
}
