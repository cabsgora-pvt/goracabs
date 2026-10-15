export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// GET → is this driver locked out pending a fresh face check? Polled on app
// open / before letting the driver toggle online.
export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver: any = await Driver.findById(payload.id)
      .select('faceVerificationRequired faceVerificationReason faceSignature')
      .lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    return withCors({
      required: driver.faceVerificationRequired === true,
      reason: driver.faceVerificationReason || null,
      // The app uses this to decide whether to prompt "set up face ID" at all
      // vs. treat the driver as pre-face-verification-feature.
      hasSignature: Array.isArray(driver.faceSignature) && driver.faceSignature.length > 0,
    })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
