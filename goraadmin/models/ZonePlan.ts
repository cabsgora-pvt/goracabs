import mongoose, { Schema } from 'mongoose'

// Subscription plans the super admin sells to zone admins (franchise). A plan
// is chosen when a zone admin is added or renewed; nobody buys one themselves.
const ZonePlanSchema = new Schema({
  name: { type: String, required: true },
  months: { type: Number, required: true, min: 1, max: 60 },
  price: { type: Number, required: true, min: 0 },   // ₹ for the whole period
  description: String,
  // What a zone admin on this plan may do in their panel (lib/zone-features).
  features: { type: [String], default: ['pricing', 'reports', 'live_map'] },
  isActive: { type: Boolean, default: true },
}, { timestamps: true })

export default mongoose.models.ZonePlan || mongoose.model('ZonePlan', ZonePlanSchema)
