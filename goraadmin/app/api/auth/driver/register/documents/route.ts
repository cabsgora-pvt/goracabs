export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { missingRequiredDocs } from '@/lib/doc-types'
import { registrationLocked, LOCKED_CODE } from '@/lib/driver-registration'
import { uploadRef } from '@/lib/ride-view'

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

    // Every image must be a file uploaded through /api/upload.
    const docsIn: any[] = []
    for (const doc of documents.slice(0, 30)) {
      const front = uploadRef(doc?.frontUrl || doc?.fileUrl, req)
      if (!front) return withCors({ error: `${doc?.name || 'Document'}: upload the photo again`, code: 'BAD_FILE_URL' }, 400)
      let back: string | undefined
      if (doc?.backUrl) {
        const b2 = uploadRef(doc.backUrl, req)
        if (!b2) return withCors({ error: `${doc?.name || 'Document'}: upload the back photo again`, code: 'BAD_FILE_URL' }, 400)
        back = b2
      }
      docsIn.push({
        name: String(doc.name || '').slice(0, 80),
        type: doc.type ? String(doc.type).slice(0, 60) : undefined,
        number: doc.number != null ? String(doc.number).slice(0, 60) : undefined,
        fileUrl: front,
        frontUrl: front,
        backUrl: back,
        expiryDate: doc.expiryDate ? String(doc.expiryDate).slice(0, 10) : undefined,
        status: 'pending',
        uploadedAt: new Date(),
      })
    }

    await connectDB()
    const current: any = await Driver.findById(payload.id).select('status registrationStep documents selectedVehicleTypeName vehicleType').lean()
    if (!current) return withCors({ error: 'Driver not found' }, 404)

    // Under review / approved (lib/driver-registration.ts): documents may only
    // be ADDED — a type not on file yet, or one an admin rejected. A verified
    // or pending document is never replaced, and the driver's status and
    // registration step are left alone.
    if (registrationLocked(current)) {
      const existing: any[] = current.documents || []
      const keyOf = (d: any) => String(d.type || d.name || '').toLowerCase()
      const byKey = new Map<string, any>(existing.map(d => [keyOf(d), d]))
      const added = docsIn.filter(d => { const e = byKey.get(keyOf(d)); return !e || e.status === 'rejected' })
      if (!added.length) {
        return withCors({ error: 'Your documents are already submitted. Contact support to change a document.', code: LOCKED_CODE }, 409)
      }
      const addedKeys = new Set(added.map(keyOf))
      const merged = [...existing.filter(d => !addedKeys.has(keyOf(d))), ...added]
      const missing = await missingRequiredDocs(merged, current.selectedVehicleTypeName || current.vehicleType)
      const incomplete = missing.filter(m => addedKeys.has(String(m.key).toLowerCase()))
      if (incomplete.length) {
        return withCors({ error: `Please complete: ${incomplete.map(m => m.name).join(', ')}`, missing: incomplete.map(m => m.key) }, 400)
      }
      await Driver.updateOne({ _id: payload.id }, { $set: { documents: merged } })
      return withCors({
        success: true, registrationStep: current.registrationStep,
        added: added.map(d => d.type || d.name),
        ignored: docsIn.filter(d => !addedKeys.has(keyOf(d))).map(d => d.type || d.name),
      })
    }

    const missing = await missingRequiredDocs(docsIn, current.selectedVehicleTypeName || current.vehicleType)
    if (missing.length) {
      return withCors({ error: `Please upload: ${missing.map(m => m.name).join(', ')}`, missing: missing.map(m => m.key) }, 400)
    }

    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      finish === true
        ? { documents: docsIn, registrationStep: 'submitted', status: 'pending' }
        : { documents: docsIn, registrationStep: 'bank' },
      { new: true }
    ).select('_id').lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, registrationStep: finish === true ? 'submitted' : 'bank' })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
