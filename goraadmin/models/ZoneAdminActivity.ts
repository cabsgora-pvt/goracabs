import mongoose, { Schema } from 'mongoose'

// What happened on a zone admin account and who did it: the zone admin, one
// of their staff, or the super admin. Kept for disputes over fares and access.
const ZoneAdminActivitySchema = new Schema({
  zoneAdminId: { type: Schema.Types.ObjectId, ref: 'ZoneAdmin', required: true, index: true },
  actorType: { type: String, enum: ['zone_admin', 'staff', 'super_admin'], required: true },
  actorName: String,
  action: { type: String, required: true },   // e.g. 'login', 'pricing.update'
  details: Schema.Types.Mixed,
}, { timestamps: true })

ZoneAdminActivitySchema.index({ zoneAdminId: 1, createdAt: -1 })

export default mongoose.models.ZoneAdminActivity || mongoose.model('ZoneAdminActivity', ZoneAdminActivitySchema)
