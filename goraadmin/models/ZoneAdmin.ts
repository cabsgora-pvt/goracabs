import mongoose, { Schema } from 'mongoose'

// A franchise holder who runs one or more zones on a paid subscription.
// Created and renewed by the super admin; signs in to the zone panel and sees
// only their own zones. Access ends with the subscription (see lib/zone-admin).

const SubscriptionPaymentSchema = new Schema({
  planId: { type: Schema.Types.ObjectId, ref: 'ZonePlan' },
  planName: String,
  invoiceNo: String,
  amount: { type: Number, default: 0 },     // ₹ paid to the super admin
  months: { type: Number, default: 1 },
  paymentRef: String,                       // UPI / bank / Razorpay reference
  notes: String,
  periodStart: Date,
  periodEnd: Date,
  recordedBy: String,                       // super admin email
}, { timestamps: true })

const ZoneAdminSchema = new Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true, lowercase: true, trim: true },
  phone: String,
  password: { type: String, required: true },
  businessName: String,
  address: String,
  gstNumber: String,
  zoneIds: [{ type: Schema.Types.ObjectId, ref: 'Zone' }],
  // Super admin's switch, separate from expiry: a blocked admin stays blocked
  // even inside a paid period.
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  // Panel features, copied from the plan when one is given; the super admin
  // can adjust them per zone admin afterwards.
  features: { type: [String], default: [] },
  // Share of the platform commission earned in their zones that is owed to
  // them. Bookkeeping only: nothing is paid out automatically.
  revenueSharePercent: { type: Number, default: 0, min: 0, max: 100 },
  // How far (±%) they may move a fare from the super admin's value.
  priceChangeLimitPct: { type: Number, default: 30, min: 0, max: 1000 },
  payouts: [new Schema({
    month: String,            // YYYY-MM the share was for
    amount: Number,
    paymentRef: String,
    notes: String,
    recordedBy: String,
  }, { timestamps: true })],
  passwordResetRequestedAt: Date,
  subscriptionEndAt: Date,
  payments: [SubscriptionPaymentSchema],
  lastLoginAt: Date,
}, { timestamps: true })

export default mongoose.models.ZoneAdmin || mongoose.model('ZoneAdmin', ZoneAdminSchema)
