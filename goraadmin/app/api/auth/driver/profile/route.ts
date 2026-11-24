export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { holdOf, holdMessage } from '@/lib/account-hold'

export async function OPTIONS() {
  return corsOptions()
}

export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    if (driver.status === 'deleted') return withCors({ error: 'Driver not found', accountDeleted: true }, 401)

    // The profile photo is the face captured at registration, and drivers
    // cannot replace it. One set before this rule (a gallery photo picked
    // after the scan) is put back to the scan here, so riders see the same face.
    if (driver.faceReferencePhotoUrl && driver.profilePicUrl !== driver.faceReferencePhotoUrl) {
      await Driver.updateOne({ _id: driver._id }, { $set: { profilePicUrl: driver.faceReferencePhotoUrl } })
      driver.profilePicUrl = driver.faceReferencePhotoUrl
    }

    const hold = holdOf(driver)
    driver.hold = hold.held ? { kind: hold.kind, reason: hold.reason, message: holdMessage(hold) } : null
    return withCors({ driver })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
