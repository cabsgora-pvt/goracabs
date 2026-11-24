export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import User from '@/models/User'
import { requireRider } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// The fields a parcel's RECEIVER needs: what is coming, from whom, where it is,
// and the drop OTP they read out to the driver at handover.
const FIELDS = [
  'service', 'status', 'deliveryPhase', 'senderName', 'receiverName', 'itemType', 'weightKg',
  'packageSize', 'isFragile', 'codAmount', 'pickupAddress', 'dropAddress', 'pickupLat', 'pickupLng',
  'dropLat', 'dropLng', 'dropOtp', 'dropOtpLocked', 'driverId', 'driverName', 'createdAt',
  'acceptedAt', 'startedAt', 'collectedAt', 'deliveredAt', 'failReason', 'scheduledAt',
].join(' ')

// GET → parcels addressed TO the signed-in rider (receiverPhone = their phone),
// newest 50. Indexed on receiverPhoneNorm (last 10 digits, set on save);
// parcels booked before that field existed are matched on the common stored
// formats of the same number.
export async function GET(req: NextRequest) {
  try {
    const payload = requireRider(req) as any
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const u: any = await User.findById(payload.id).select('phone').lean()
    const phone = String(u?.phone || '').replace(/\D/g, '').slice(-10)
    if (phone.length !== 10) return withCors({ rides: [] })

    // Legacy rows (no receiverPhoneNorm): the same 10 digits with any
    // separators / +91 / 0 prefix in between. Matches are backfilled so the
    // next lookup is the indexed one.
    const legacy = new RegExp('^\\D*(?:91)?\\D*0?\\D*' + phone.split('').join('\\D*') + '\\D*$')
    const mine: any[] = await Ride.find({
      service: 'delivery',
      $or: [{ receiverPhoneNorm: phone }, { receiverPhoneNorm: null, receiverPhone: legacy }],
    }).sort({ createdAt: -1 }).limit(50).select(FIELDS + ' receiverPhoneNorm').lean()
    const backfill = mine.filter(r => !r.receiverPhoneNorm).map(r => r._id)
    if (backfill.length) Ride.updateMany({ _id: { $in: backfill } }, { $set: { receiverPhoneNorm: phone } }).catch(() => {})

    const driverIds = Array.from(new Set(mine.map(r => r.driverId).filter(Boolean).map(String)))
    const drivers = driverIds.length ? await Driver.find({ _id: { $in: driverIds } }).select('name profilePicUrl vehicleModel vehicleNumber').lean() as any[] : []
    const dMap = new Map(drivers.map(d => [String(d._id), d]))

    const rides = mine.map(r => {
      const d = r.driverId ? dMap.get(String(r.driverId)) : null
      // The OTP only matters while the parcel is on its way.
      const live = !['completed', 'cancelled'].includes(r.status) && !['delivered', 'returned', 'failed'].includes(r.deliveryPhase)
      const { driverId: _d, dropOtp, receiverPhoneNorm: _n, ...rest } = r
      return {
        ...rest,
        ...(live ? { dropOtp } : {}),
        driver: d ? { name: d.name, profilePicUrl: d.profilePicUrl, vehicleModel: d.vehicleModel, vehicleNumber: d.vehicleNumber } : null,
      }
    })
    return withCors({ rides })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
