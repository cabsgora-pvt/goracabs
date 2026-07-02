import mongoose, { Schema } from 'mongoose'

// Admin-managed driver subscription plans (Rapido-style zero/low-commission passes).
// While a driver has an active plan, ride commission is overridden to
// `commissionPercentWhileActive` (usually 0) instead of the zone commission.
const SubscriptionPlanSchema = new Schema({
  name: { type: String, required: true },        // "Weekly Pass"
  price: { type: Number, required: true },        // ₹149
  durationDays: { type: Number, required: true }, // 7 / 30 / 1
  description: { type: String, default: '' },
  benefits: { type: [String], default: [] },      // bullet points shown in driver app
  commissionPercentWhileActive: { type: Number, default: 0 }, // 0 = zero commission
  services: { type: [String], default: [] },      // empty = all services
  vehicleTypes: { type: [String], default: [] },  // empty = all vehicle types
  isActive: { type: Boolean, default: true },
  sortOrder: { type: Number, default: 0 },
}, { timestamps: true })

export default mongoose.models.SubscriptionPlan || mongoose.model('SubscriptionPlan', SubscriptionPlanSchema)
