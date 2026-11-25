import mongoose, { Schema } from 'mongoose'

// Who did what in the super admin dashboard. One row per admin mutation:
// guardAdmin writes a generic row for every non-GET admin API call, and the
// money / pricing / destructive routes enrich that same row (action, target,
// summary) through lib/admin-audit auditAdmin. Kept 2 years (TTL on `at`).
const AdminAuditSchema = new Schema({
  adminId: { type: Schema.Types.ObjectId, ref: 'Admin', index: true },
  email: String,
  action: { type: String, required: true },   // e.g. 'driver.wallet.adjust', or 'api.POST'
  method: String,
  path: String,
  target: String,                             // id (or "kind:id") the action touched
  summary: String,                            // short human text, no secrets
  details: Schema.Types.Mixed,
  ip: String,
  at: { type: Date, default: Date.now },
}, { versionKey: false })

AdminAuditSchema.index({ at: -1 })
AdminAuditSchema.index({ action: 1, at: -1 })
AdminAuditSchema.index({ at: 1 }, { expireAfterSeconds: 2 * 365 * 86400 })

export default mongoose.models.AdminAudit || mongoose.model('AdminAudit', AdminAuditSchema)
