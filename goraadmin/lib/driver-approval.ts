import Driver from '@/models/Driver'
import { missingRequiredDocs } from '@/lib/doc-types'

// ─────────────────────────────────────────────────────────────────────────────
// Who may be approved. Shared by the super admin (POST /api/drivers/{id}/approve)
// and the zone admin (POST /api/zone-admin/drivers/{id} action 'approve'):
//   • status pending or rejected — never deleted, blocked or already approved
//   • registration submitted (registrationStep 'submitted')
//   • every required document present (lib/doc-types missingRequiredDocs)
// The status change itself is conditional on the same status/step, so a
// driver deleted or re-opened between the check and the write is not approved.
// ─────────────────────────────────────────────────────────────────────────────

export const APPROVABLE_STATUSES = ['pending', 'rejected']

export type ApprovalCheck = { ok: true } | { ok: false; status: number; error: string; code: string; missing?: { key: string; name: string }[] }

export async function approvalBlocker(d: any): Promise<ApprovalCheck> {
  if (!d) return { ok: false, status: 404, error: 'Driver not found', code: 'NOT_FOUND' }
  if (d.status === 'deleted') return { ok: false, status: 409, error: 'This driver account was deleted', code: 'DRIVER_DELETED' }
  if (!APPROVABLE_STATUSES.includes(d.status)) {
    return { ok: false, status: 409, error: `Driver is ${d.status || 'in an unknown state'} — only pending or rejected drivers can be approved`, code: 'NOT_APPROVABLE' }
  }
  if (d.registrationStep !== 'submitted') {
    return { ok: false, status: 409, error: 'Driver has not submitted the registration yet', code: 'NOT_SUBMITTED' }
  }
  const missing = await missingRequiredDocs(d.documents || [], d.selectedVehicleTypeName || d.vehicleType)
  if (missing.length) {
    return { ok: false, status: 409, error: `Missing required documents: ${missing.map(m => m.name).join(', ')}`, code: 'DOCS_MISSING', missing }
  }
  return { ok: true }
}

/** Approve atomically, only from the state that was checked. Returns the
 *  updated driver (lean, without face signature) or null if it changed. */
export async function approveDriverAtomic(id: any, extraSet: Record<string, any> = {}) {
  return Driver.findOneAndUpdate(
    { _id: id, status: { $in: APPROVABLE_STATUSES }, registrationStep: 'submitted' },
    { $set: { status: 'approved', ...extraSet } },
    { new: true },
  ).select('-faceSignature -walletRechargeRefs').lean()
}
