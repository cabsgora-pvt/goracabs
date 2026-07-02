import mongoose, { Schema } from 'mongoose'

// One row per subscription purchase — full history of a driver's memberships.
const DriverSubscriptionSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver', index: true },
  planId: { type: Schema.Types.ObjectId, ref: 'SubscriptionPlan' },
  planName: String,
  price: Number,
  durationDays: Number,
  commissionPercentWhileActive: { type: Number, default: 0 },
  startedAt: Date,
  expiresAt: Date,
  status: { type: String, enum: ['active', 'expired', 'cancelled'], default: 'active' },
}, { timestamps: true })

export default mongoose.models.DriverSubscription || mongoose.model('DriverSubscription', DriverSubscriptionSchema)
