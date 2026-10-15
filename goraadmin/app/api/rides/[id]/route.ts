export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { uiPhaseFor, waitingSecondsFor } from '@/lib/ride-phase'
import User from '@/models/User'
import { rentalExtras, hireExtras } from '@/lib/ride-extras'
import { requireAuth, requireDriverAuth, isAdminPayload } from '@/lib/auth'

// GET ride by id — also returns hydrated driver + rider sub-objects
// (driver photo, plate, model, rating; rider photo) so both apps can render rich cards.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const asUser = requireAuth(req) as any
    const asDriver = requireDriverAuth(req) as any
    if (!asUser?.id && !asDriver?.id) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    await connectDB()
    const ride: any = await Ride.findById(params.id).lean()
    if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })

    // Who may read it: an admin and the rider see everything; the assigned
    // driver, or any driver while the request is still open, see it without
    // the OTPs (the rider reads those out — a driver who could fetch them would
    // make the check pointless). Anyone else gets nothing.
    const isAdmin = isAdminPayload(asUser)
    const isRider = asUser?.type === 'user' && String(ride.riderId || '') === String(asUser.id)
    const isDriver = asDriver?.type === 'driver'
    const isAssigned = isDriver && String(ride.driverId || '') === String(asDriver.id)
    if (!isAdmin && !isRider && !isAssigned && !(isDriver && ride.status === 'pending')) {
      return NextResponse.json({ error: 'Not a participant in this ride' }, { status: 403 })
    }
    if (!isAdmin && !isRider) {
      delete ride.otp
      delete ride.dropOtp
      if (!isAssigned) delete ride.riderPhone
    }

    if (ride.driverId) {
      const d: any = await Driver.findById(ride.driverId)
        .select('name phone profilePicUrl vehicleModel vehicleNumber vehicleRegistrationNumber rating totalRides createdAt currentLat currentLng currentHeading locationUpdatedAt selectedVehicleTypeName')
        .lean()
      if (d) {
        // Driver "experience" = years on platform (rounded down)
        let yearsActive = 0
        if (d.createdAt) {
          const ms = Date.now() - new Date(d.createdAt).getTime()
          yearsActive = Math.max(1, Math.floor(ms / (1000 * 60 * 60 * 24 * 365)))
        }
        ride.driver = {
          id: d._id,
          name: d.name,
          phone: d.phone,
          profilePicUrl: d.profilePicUrl,
          vehicleModel: d.vehicleModel,
          vehicleNumber: d.vehicleNumber || d.vehicleRegistrationNumber,
          rating: d.rating,
          totalRides: d.totalRides,
          yearsActive,
          currentLat: d.currentLat,
          currentLng: d.currentLng,
          currentHeading: d.currentHeading,
          locationUpdatedAt: d.locationUpdatedAt,
          vehicleTypeName: d.selectedVehicleTypeName,
        }
      }
    }

    if (ride.riderId) {
      const u: any = await User.findById(ride.riderId).select('name phone profilePicUrl').lean()
      if (u) ride.rider = {
        id: u._id,
        name: u.name,
        phone: isAdmin || isRider || isAssigned ? u.phone : undefined,
        profilePicUrl: u.profilePicUrl,
      }
    }

    // One computed phase, so both apps stop re-deriving "what is happening now"
    // from five separate fields and drifting apart at the edges. The underlying
    // fields are still returned, so existing readers are unaffected.
    const ui = uiPhaseFor(ride)
    ride.uiPhase = ui.phase
    ride.uiPhaseLabel = ui.label
    ride.uiPhaseOverrun = ui.overrun
    ride.waitingSec = waitingSecondsFor(ride)

    // The rider could not see extras accruing at all: the live total was only
    // computed on the DRIVER's ping routes. Same shared formula, so the figure a
    // rider watches is the figure they are billed. Projection only — never saved.
    if (ride.service === 'rental' && ride.status === 'ongoing') {
      const ex = rentalExtras(ride)
      ride.liveExtraHours = ex.extraHours
      ride.liveExtraKm = ex.extraKm
      ride.liveExtraCharge = Math.round(ex.total)
    } else if (ride.service === 'hire_driver' && ride.status === 'ongoing') {
      const ex = hireExtras(ride)
      ride.liveExtraHours = ex.extraHours
      ride.liveExtraCharge = Math.round(ex.extraCharge)
    }

    return NextResponse.json(ride)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
