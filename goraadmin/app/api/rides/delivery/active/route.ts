export const dynamic = 'force-dynamic'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → active deliveries (accepted/ongoing) with their driver's live position, for the admin map
export async function GET() {
  try {
    await connectDB()
    const rides: any[] = await Ride.find({
      service: 'delivery',
      status: { $in: ['accepted', 'arrived', 'ongoing'] },
    }).sort({ createdAt: -1 }).limit(100).lean()

    const driverIds = Array.from(new Set(rides.map(r => r.driverId).filter(Boolean).map(String)))
    const drivers = driverIds.length
      ? await Driver.find({ _id: { $in: driverIds } }).select('name currentLat currentLng currentHeading vehicleNumber').lean() as any[]
      : []
    const dMap = new Map(drivers.map(d => [String(d._id), d]))

    const result = rides.map(r => {
      const d: any = r.driverId ? dMap.get(String(r.driverId)) : null
      return {
        id: r._id,
        senderName: r.senderName, receiverName: r.receiverName,
        itemType: r.itemType, deliveryPhase: r.deliveryPhase,
        pickupLat: r.pickupLat, pickupLng: r.pickupLng,
        dropLat: r.dropLat, dropLng: r.dropLng,
        driverName: d?.name || r.driverName,
        driverLat: d?.currentLat, driverLng: d?.currentLng, driverHeading: d?.currentHeading,
        vehicleNumber: d?.vehicleNumber,
      }
    })
    return withCors({ deliveries: result })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
