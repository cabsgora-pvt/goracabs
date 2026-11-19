import mongoose, { Schema } from 'mongoose'

// An operator a zone admin adds to their own panel, with fewer permissions.
// Signs in at the same zone panel login; never outlives the zone admin's own
// access (lib/zone-admin checks the owner on every request).
const ZoneStaffSchema = new Schema({
  zoneAdminId: { type: Schema.Types.ObjectId, ref: 'ZoneAdmin', required: true, index: true },
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  phone: String,
  password: { type: String, required: true },
  // Subset of the zone admin's own features (lib/zone-features).
  permissions: { type: [String], default: [] },
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  passwordResetRequestedAt: Date,
  lastLoginAt: Date,
}, { timestamps: true })

export default mongoose.models.ZoneStaff || mongoose.model('ZoneStaff', ZoneStaffSchema)
