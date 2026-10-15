import mongoose, { Schema } from 'mongoose'
const SOSSchema = new Schema({
  name: String,
  phone: String,
  relation: String,
  addedBy: { type: String, enum: ['admin', 'driver', 'user'], default: 'admin' },
  // Who a self-added contact belongs to. Admin contacts leave this null and are
  // shown to everyone; a driver's own contacts are visible only to them.
  ownerId: { type: String, default: null, index: true },
  isActive: { type: Boolean, default: true },
}, { timestamps: true })
export default mongoose.models.SOSContact || mongoose.model('SOSContact', SOSSchema)
