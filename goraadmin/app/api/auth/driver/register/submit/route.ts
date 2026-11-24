export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { missingRequiredDocs } from '@/lib/doc-types'

export async function OPTIONS() {
  return corsOptions()
}

// POST → submits a registration for review without bank details.
// Registration no longer asks for a bank account. A driver whose documents
// were saved by an older app build sits at registrationStep 'bank'; the
// current app calls this to finish. The saved documents must still be
// complete. Bank details can be added later (withdrawals ask for them).
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    await connectDB()
    const d: any = await Driver.findById(payload.id).select('registrationStep documents selectedVehicleTypeName vehicleType').lean()
    if (!d) return withCors({ error: 'Driver not found' }, 404)
    if (d.registrationStep === 'submitted') return withCors({ success: true, registrationStep: 'submitted' })
    if (d.registrationStep !== 'bank') return withCors({ error: 'Please finish the earlier registration steps first' }, 400)
    const missing = await missingRequiredDocs(d.documents || [], d.selectedVehicleTypeName || d.vehicleType)
    if (missing.length) {
      return withCors({ error: `Please upload: ${missing.map(m => m.name).join(', ')}`, missing: missing.map(m => m.key) }, 400)
    }
    await Driver.updateOne({ _id: payload.id, registrationStep: 'bank' }, { $set: { registrationStep: 'submitted', status: 'pending' } })
    return withCors({ success: true, registrationStep: 'submitted' })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
