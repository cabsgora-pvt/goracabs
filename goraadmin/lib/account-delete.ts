import Driver from '@/models/Driver'
import User from '@/models/User'
import Ride from '@/models/Ride'
import Upload from '@/models/Upload'
import FaceVerification from '@/models/FaceVerification'
import crypto from 'crypto'
import { deleteStoredFiles } from '@/lib/private-files'
import { invalidateAccountCache } from '@/lib/auth'

// ─────────────────────────────────────────────────────────────────────────────
// Soft delete for a rider or driver account. Used by the account-request
// approval (person asked to close their account) and by the admin DELETE
// buttons — there is no hard delete any more, so ride and transaction history
// (needed for accounts, refunds and disputes) always keeps its owner record.
//
// What it does:
//   • status 'deleted', deletedAt now, name -> 'Deleted user/driver', email ''
//   • phone -> 'deleted_<ts>_<hash>_<last4>' so the number can sign up again
//     later; the full number is not kept (sha256 prefix + last 4 for support)
//   • tokenVersion bumped: every open session of the account is revoked
//   • the person's KYC files are removed from disk: document images, face
//     reference photo, face-check photos (drivers), ID photo (riders), and any
//     private upload they own (models/Upload)
//   • PII blanked (minimal, documented): documents, bankDetails, bankAccounts,
//     faceSignature + faceReferencePhotoUrl (drivers); idNumber, idPhotoUrl
//     (riders); fcmToken (both). Kept: id, walletBalance, ride/rating counters.
//   • drivers go offline.
//
// Refuses (409) while the person has a ride in progress, and — when
// requireZeroBalance is set (admin delete) — while the wallet is not zero, so
// money is never stranded on an account nobody can sign in to.
// ─────────────────────────────────────────────────────────────────────────────

export type DeleteResult = { ok: true } | { ok: false; status: number; error: string }

const DRIVER_BUSY = ['accepted', 'arrived', 'ongoing']
const RIDER_BUSY = ['pending', 'accepted', 'arrived', 'ongoing']

export async function softDeleteAccount(
  kind: 'rider' | 'driver',
  id: string,
  opts: { requireZeroBalance?: boolean } = {},
): Promise<DeleteResult> {
  const Model: any = kind === 'driver' ? Driver : User
  const doc: any = await Model.findById(id).select('phone status walletBalance documents faceReferencePhotoUrl idPhotoUrl').lean()
  if (!doc) return { ok: false, status: 404, error: 'Account no longer exists' }
  if (doc.status === 'deleted') return { ok: false, status: 409, error: 'Account is already deleted' }

  const busy = kind === 'driver'
    ? await Ride.exists({ driverId: doc._id, status: { $in: DRIVER_BUSY } })
    : await Ride.exists({ riderId: doc._id, status: { $in: RIDER_BUSY } })
  if (busy) {
    return { ok: false, status: 409, error: `${kind === 'driver' ? 'Driver' : 'Rider'} has a ride in progress — try after it ends` }
  }

  const bal = Number(doc.walletBalance || 0)
  if (opts.requireZeroBalance && Math.abs(bal) >= 0.01) {
    return { ok: false, status: 409, error: `Wallet balance is ₹${bal.toFixed(2)} — settle it to ₹0 before deleting this account` }
  }

  const set: Record<string, any> = {
    status: 'deleted',
    deletedAt: new Date(),
    name: kind === 'driver' ? 'Deleted driver' : 'Deleted user',
    phone: deletedPhone(doc.phone),
    email: '',
    fcmToken: '',
  }
  const unset: Record<string, ''> = {}
  if (kind === 'driver') {
    Object.assign(set, { isOnline: false, documents: [], bankAccounts: [] })
    Object.assign(unset, { bankDetails: '', faceSignature: '', faceReferencePhotoUrl: '' })
  } else {
    Object.assign(unset, { idNumber: '', idPhotoUrl: '' })
  }

  // Guard the write on what we checked, so a concurrent wallet credit or a
  // second delete cannot slip between the checks and the update.
  const filter: any = { _id: doc._id, status: { $ne: 'deleted' }, phone: doc.phone }
  if (opts.requireZeroBalance) {
    filter.$or = [{ walletBalance: { $exists: false } }, { walletBalance: null }, { walletBalance: { $gt: -0.01, $lt: 0.01 } }]
  }
  const r = await Model.updateOne(filter, { $set: set, $unset: unset, $inc: { tokenVersion: 1 } }, { strict: false })
  if (!r.matchedCount) return { ok: false, status: 409, error: 'Account changed while deleting — reload and try again' }
  invalidateAccountCache(kind, String(doc._id))
  await removeKycFiles(kind, doc).catch(() => {})
  return { ok: true }
}

/** deleted_<ts>_<sha256(phone) 10 hex>_<last 4>: unique, frees the number, keeps
 *  no full phone. */
export function deletedPhone(phone: any): string {
  const p = String(phone || '')
  const h = crypto.createHash('sha256').update(p).digest('hex').slice(0, 10)
  return `deleted_${Date.now()}_${h}_${p.replace(/\D/g, '').slice(-4)}`
}

/** Best effort: the stored KYC images of a deleted account. Ride history files
 *  (delivery proofs) are kept — they belong to the ride record. */
async function removeKycFiles(kind: 'rider' | 'driver', doc: any) {
  const urls: string[] = []
  if (kind === 'driver') {
    for (const d of doc.documents || []) urls.push(d?.fileUrl, d?.frontUrl, d?.backUrl)
    urls.push(doc.faceReferencePhotoUrl)
    const fv: any[] = await FaceVerification.find({ driverId: doc._id }).select('photoUrl').lean().catch(() => [])
    for (const f of fv) urls.push(f?.photoUrl)
  } else {
    urls.push(doc.idPhotoUrl)
  }
  const priv: any[] = await Upload.find({ ownerType: kind, ownerId: String(doc._id), private: true, purpose: { $ne: 'delivery_proof' } }).select('name').lean()
  for (const u of priv) urls.push('/api/files/' + u.name)
  await deleteStoredFiles(urls.filter(Boolean))
  if (priv.length) await Upload.deleteMany({ _id: { $in: priv.map(u => u._id) } })
}
