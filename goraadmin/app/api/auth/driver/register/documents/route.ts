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

// POST { documents: [{ name, type (document key), number?, frontUrl, backUrl?, expiryDate? }], finish? }
// Every REQUIRED document the admin set up (Settings → Driver App →
// Registration documents) for this driver's vehicle type must be complete —
// photo(s), number and expiry as that document asks — or nothing is saved.
// It used to accept whatever the app sent.
//
// finish: true (current driver app — registration has no bank step any more):
// the registration is submitted for review right here. Without it (older app
// builds) the driver goes on to the bank step as before.
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { documents, finish } = await req.json()
    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return withCors({ error: 'Documents are required' }, 400)
    }

    await connectDB()
    const current: any = await Driver.findById(payload.id).select('selectedVehicleTypeName vehicleType').lean()
    if (!current) return withCors({ error: 'Driver not found' }, 404)

    const missing = await missingRequiredDocs(documents, current.selectedVehicleTypeName || current.vehicleType)
    if (missing.length) {
      return withCors({ error: `Please upload: ${missing.map(m => m.name).join(', ')}`, missing: missing.map(m => m.key) }, 400)
    }

    const docs = documents.slice(0, 30).map((doc: {
      name: string; type?: string; number?: string;
      fileUrl?: string; frontUrl?: string; backUrl?: string; expiryDate?: string;
    }) => ({
      name: doc.name,
      type: doc.type,
      number: doc.number,
      fileUrl: doc.frontUrl || doc.fileUrl,
      frontUrl: doc.frontUrl || doc.fileUrl,
      backUrl: doc.backUrl,
      expiryDate: doc.expiryDate,
      status: 'pending',
      uploadedAt: new Date(),
    }))

    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      finish === true
        ? { documents: docs, registrationStep: 'submitted', status: 'pending' }
        : { documents: docs, registrationStep: 'bank' },
      { new: true }
    ).lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, registrationStep: finish === true ? 'submitted' : 'bank' })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
