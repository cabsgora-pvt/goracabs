export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { readFile } from 'fs/promises'
import path from 'path'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Upload from '@/models/Upload'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'
import { requireActiveAdmin, requireActiveDriver, requireActiveRider, requireDriverAuth, requireRider } from '@/lib/auth'
import { guardZoneAdmin } from '@/lib/zone-admin'
import { FILE_NAME_RE, PRIVATE_DIR, PRIVATE_PREFIX } from '@/lib/private-files'

// GET /api/files/<name> — a private upload (see lib/private-files). Allowed:
//   • any signed-in admin (dashboard <img> sends the admin cookie)
//   • the owner (rider / driver Bearer token, account active)
//   • a zone admin, for drivers in their zones (driver review)
//   • for a delivery proof photo: the ride's rider and driver
// Everyone else gets 404 (not 403), so file names can't be probed.
const notFound = () => NextResponse.json({ error: 'Not found' }, { status: 404 })

export async function GET(req: NextRequest, { params }: { params: { name: string } }) {
  try {
    const name = String(params.name || '')
    if (!FILE_NAME_RE.test(name)) return notFound()
    await connectDB()
    const up: any = await Upload.findOne({ name, private: true }).lean()
    if (!up) return notFound()

    let allowed = !!(await requireActiveAdmin(req))
    let callerDriver = '', callerRider = ''
    if (!allowed && requireDriverAuth(req)) {
      const a = await requireActiveDriver(req)
      if (a.ok) callerDriver = a.id
    } else if (!allowed && requireRider(req)) {
      const a = await requireActiveRider(req)
      if (a.ok) callerRider = a.id
    }
    if (!allowed && callerDriver && up.ownerType === 'driver' && up.ownerId === callerDriver) allowed = true
    if (!allowed && callerRider && up.ownerType === 'rider' && up.ownerId === callerRider) allowed = true

    if (!allowed && (callerDriver || callerRider)) {
      const url = PRIVATE_PREFIX + name
      const ride: any = await Ride.findOne({ $or: [{ deliveryProofPhoto: url }, { deliveryFailPhoto: url }] }).select('riderId driverId').lean()
      if (ride && ((callerDriver && String(ride.driverId) === callerDriver) || (callerRider && String(ride.riderId) === callerRider))) allowed = true
    }

    if (!allowed && !callerDriver && !callerRider && up.ownerType === 'driver' && mongoose.isValidObjectId(up.ownerId)) {
      const g = await guardZoneAdmin(req, { feature: 'drivers' })
      if (!('denied' in g)) {
        const d: any = await Driver.findById(up.ownerId).select('zoneId status').lean()
        if (d && d.status !== 'deleted' && g.zoneIds.includes(String(d.zoneId))) allowed = true
      }
    }
    if (!allowed) return notFound()

    let data: Buffer
    try { data = await readFile(path.join(PRIVATE_DIR(), name)) } catch { return notFound() }
    return new NextResponse(new Uint8Array(data), {
      status: 200,
      headers: {
        'Content-Type': up.mime || 'application/octet-stream',
        'Content-Length': String(data.length),
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
        'Content-Disposition': 'inline',
        'Content-Security-Policy': "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; sandbox",
      },
    })
  } catch {
    return notFound()
  }
}
