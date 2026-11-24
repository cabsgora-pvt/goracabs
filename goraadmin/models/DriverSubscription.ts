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
  // The driver's zone when they bought it, and the zone admin's part of the
  // price, fixed at purchase (lib/commission.ts). A subscribed driver pays no
  // ride commission, so in franchise mode this is how the zone admin earns
  // from them. zoneAdminId null / amount 0 = all of it is Gora's.
  zoneId: { type: Schema.Types.ObjectId, ref: 'Zone', default: null },
  paidVia: { type: String, enum: ['wallet', 'razorpay'], default: 'wallet' },
  franchiseShare: {
    type: new Schema({
      zoneAdminId: { type: Schema.Types.ObjectId, ref: 'ZoneAdmin', default: null },
      zoneId: { type: Schema.Types.ObjectId, ref: 'Zone', default: null },
      percent: Number, base: Number, amount: Number, at: Date,
    }, { _id: false }),
    default: undefined,
  },
}, { timestamps: true })

DriverSubscriptionSchema.index({ 'franchiseShare.zoneAdminId': 1, createdAt: 1 }, { sparse: true })

export default mongoose.models.DriverSubscription || mongoose.model('DriverSubscription', DriverSubscriptionSchema)
