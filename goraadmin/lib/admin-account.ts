import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import { requireAdmin } from '@/lib/auth'

// Shared by /api/users/[id]/hold and /api/drivers/[id]/hold.
// POST { active: true, kind: 'face'|'wallet'|'manual'|'other', reason }  → put on hold
// POST { active: false }                                                → release
// Releasing a driver also clears a failed face check, so they can go online.
export async function setHold(req: NextRequest, Model: any, id: string, isDriver: boolean) {
  const admin: any = requireAdmin(req)
  if (!admin) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!mongoose.isValidObjectId(id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const b = await req.json().catch(() => ({}))
  await connectDB()
  const set: any = {}
  if (b.active) {
    const kind = ['face', 'wallet', 'manual', 'other'].includes(b.kind) ? b.kind : 'manual'
    const reason = String(b.reason || '').trim().slice(0, 200)
    if (!reason) return NextResponse.json({ error: 'Please give a reason' }, { status: 400 })
    set.accountHold = { active: true, kind, reason, at: new Date(), by: admin.email || 'admin' }
    if (isDriver) set.isOnline = false
  } else {
    set['accountHold.active'] = false
    set['accountHold.at'] = new Date()
    set['accountHold.by'] = admin.email || 'admin'
    if (isDriver) { set.faceVerificationRequired = false; set.faceVerificationReason = '' }
  }
  const doc = await Model.findByIdAndUpdate(id, { $set: set }, { new: true }).lean()
  if (!doc) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ success: true, accountHold: (doc as any).accountHold || null })
}

// Fields the admin may edit on a rider / driver (edit mode). Anything else in
// the body is ignored — the old PUT wrote the whole body straight to the doc.
export const USER_EDITABLE = ['name', 'email', 'phone', 'city', 'gender', 'idNumber', 'idPhotoUrl', 'profilePicUrl', 'status']
export const DRIVER_EDITABLE = [
  'name', 'email', 'phone', 'gender', 'state', 'status', 'rejectionReason', 'registrationStep',
  'vehicleModel', 'vehicleNumber', 'vehicleRegistrationNumber', 'selectedVehicleTypeName', 'vehicleType',
  'allowTaxi', 'allowRental', 'allowOutstation', 'allowHireDriver', 'allowDelivery',
  'zoneAuto', 'ridePreferences', 'profilePicUrl', 'faceVerificationRequired', 'faceVerificationReason',
  'bankDetails.accountHolderName', 'bankDetails.bankName', 'bankDetails.branch',
  'bankDetails.accountNumber', 'bankDetails.ifscCode', 'bankDetails.accountType',
]

/** Cleans the parts of a driver document an admin may set. */
export function cleanDriverDoc(b: any): { fields: Record<string, string> } | { error: string } {
  const fields: Record<string, string> = {}
  if (b.status !== undefined) {
    if (!['pending', 'verified', 'rejected'].includes(b.status)) return { error: 'Invalid document status' }
    fields.status = b.status
  }
  if (typeof b.name === 'string' && b.name.trim()) fields.name = b.name.trim().slice(0, 60)
  if (typeof b.number === 'string') fields.number = b.number.trim().slice(0, 40)
  if (typeof b.expiryDate === 'string') {
    const e = b.expiryDate.trim()
    if (e && !/^\d{4}-\d{2}-\d{2}$/.test(e)) return { error: 'Expiry must be a date (YYYY-MM-DD)' }
    fields.expiryDate = e
  }
  for (const k of ['frontUrl', 'backUrl']) {
    if (typeof b[k] === 'string') {
      const u = b[k].trim()
      if (u && !/^(https?:\/\/|\/uploads\/)/.test(u)) return { error: 'Photo must be an uploaded file' }
      fields[k] = u
    }
  }
  return { fields }
}

export const REGISTRATION_STEPS =['otp', 'personal', 'face', 'vehicle', 'documents', 'bank', 'submitted']

/**
 * Checks and normalises the fields an admin edit may send, for both riders and
 * drivers. Returns an error message, or null when the body is fine (it is
 * cleaned in place: trimmed, upper-cased IFSC, digits-only account number).
 */
export function validateAccountEdit(body: any): string | null {
  for (const k of Object.keys(body)) if (typeof body[k] === 'string') body[k] = body[k].trim()
  if ('name' in body && !body.name) return 'Name cannot be empty'
  if (body.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)) return 'Enter a valid email'
  if ('gender' in body && body.gender === '') body.gender = undefined
  if (body.gender !== undefined && !['male', 'female', 'other'].includes(body.gender)) return 'Invalid gender'
  if (body.registrationStep !== undefined && !REGISTRATION_STEPS.includes(body.registrationStep)) return 'Invalid registration step'
  if (body['bankDetails.ifscCode']) {
    body['bankDetails.ifscCode'] = String(body['bankDetails.ifscCode']).toUpperCase()
    if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(body['bankDetails.ifscCode'])) return 'IFSC must look like SBIN0001234'
  }
  if (body['bankDetails.accountNumber']) {
    body['bankDetails.accountNumber'] = String(body['bankDetails.accountNumber']).replace(/\s/g, '')
    if (!/^\d{6,18}$/.test(body['bankDetails.accountNumber'])) return 'Account number must be 6–18 digits'
  }
  if (body['bankDetails.accountType'] !== undefined && !['savings', 'current'].includes(body['bankDetails.accountType'])) return 'Account type must be savings or current'
  for (const k of ['profilePicUrl', 'idPhotoUrl']) {
    if (body[k] && !/^(https?:\/\/|\/uploads\/)/.test(body[k])) return 'Photo must be an uploaded file'
  }
  return null
}

export function pick(body: any, keys: string[]) {
  const out: any = {}
  for (const k of keys) if (body && Object.prototype.hasOwnProperty.call(body, k)) out[k] = body[k]
  return out
}
