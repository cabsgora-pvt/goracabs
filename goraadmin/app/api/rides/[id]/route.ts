export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import Driver from '@/models/Driver'
import { uiPhaseFor, waitingSecondsFor } from '@/lib/ride-phase'
import User from '@/models/User'
import { rentalExtras, hireExtras } from '@/lib/ride-extras'
import { requireAuth, requireDriverAuth, isAdminPayload } from '@/lib/auth'
import { expireIfNoDriver, driverEligibleFor, cachedGlobalSettings } from '@/lib/dispatch'
import { driverSafeRide, withoutPhones, ACTIVE_STATUSES } from '@/lib/ride-view'
import mongoose from 'mongoose'

// GET ride by id — also returns hydrated driver + rider sub-objects
// (driver photo, plate, model, rating; rider photo) so both apps can render rich cards.
export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const asUser = requireAuth(req) as any
    const asDriver = requireDriverAuth(req) as any
    if (!asUser?.id && !asDriver?.id) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    await connectDB()
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
    // ?lite=1: everything but the chat (the rider's 3 s poll after its first
    // full load — the chat has its own endpoint).
    const lite = req.nextUrl?.searchParams?.get('lite') === '1'
    let ride: any = await Ride.findById(params.id).select(lite ? '-messages' : '').lean()
    if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })

    // Who may read it: an admin and the rider see everything; the assigned
    // driver sees it without the OTPs (the rider reads those out). A pending
    // request is readable only by a driver who could take it (the same rule
    // as accept and the feed) or the driver it is offered to — not by any
    // driver who knows the id. Anyone else gets nothing.
    const isAdmin = isAdminPayload(asUser)
    const isRider = asUser?.type === 'user' && String(ride.riderId || '') === String(asUser.id)
    const isDriver = asDriver?.type === 'driver'
    const isAssigned = isDriver && String(ride.driverId || '') === String(asDriver.id)
    let openToThisDriver = false
    if (!isAdmin && !isRider && !isAssigned && isDriver && ride.status === 'pending') {
      if (ride.offeredTo && String(ride.offeredTo) === String(asDriver.id)) openToThisDriver = true
      else {
        const me: any = await Driver.findById(asDriver.id).lean()
        openToThisDriver = !!me && (await driverEligibleFor(me, ride, { settings: await cachedGlobalSettings() })) === null
      }
    }
    if (!isAdmin && !isRider && !isAssigned && !openToThisDriver) {
      return NextResponse.json({ error: 'Not a participant in this ride' }, { status: 403 })
    }
    // The rider polls this every 3 s while searching, so this is where a ride
    // nobody took is closed as "No driver found" (no-op unless overdue; see
    // lib/dispatch.ts). Re-read so this very answer carries the new state.
    if (ride.status === 'pending' && await expireIfNoDriver(ride._id).catch(() => false)) {
      ride = await Ride.findById(params.id).select(lite ? '-messages' : '').lean()
      if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
    }

    // The driver's live position, and the rider's / driver's phone numbers,
    // are only shared while the trip is live.
    const live = ACTIVE_STATUSES.includes(ride.status)
    if (!isAdmin && !isRider) {
      ride = driverSafeRide(ride)
      if (!isAssigned) {
        // An open request: names and area only until a driver accepts it.
        delete ride.messages; delete ride.deliveryStops
        delete ride.rejectedBy; delete ride.offeredHistory
      }
      if (!isAssigned || !live) ride = withoutPhones(ride)
    } else if (isRider && !live) {
      delete ride.driverPhone
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
          phone: live || isAdmin ? d.phone : undefined,
          profilePicUrl: d.profilePicUrl,
          vehicleModel: d.vehicleModel,
          vehicleNumber: d.vehicleNumber || d.vehicleRegistrationNumber,
          rating: d.rating,
          totalRides: d.totalRides,
          yearsActive,
          currentLat: live ? d.currentLat : undefined,
          currentLng: live ? d.currentLng : undefined,
          currentHeading: live ? d.currentHeading : undefined,
          locationUpdatedAt: live ? d.locationUpdatedAt : undefined,
          vehicleTypeName: d.selectedVehicleTypeName,
        }
      }
    }

    if (ride.riderId) {
      const u: any = await User.findById(ride.riderId).select('name phone profilePicUrl').lean()
      if (u) ride.rider = {
        id: u._id,
        name: u.name,
        phone: isAdmin || isRider || (isAssigned && live) ? u.phone : undefined,
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
