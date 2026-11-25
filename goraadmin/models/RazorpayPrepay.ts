import mongoose, { Schema } from 'mongoose'

// An outstation prepayment Razorpay reported as captured (webhook), kept until
// a booking links it (Ride.prepaidRef = paymentId) or the orphan sweep refunds
// it to the rider's wallet (lib/prepay.ts sweepOrphanPrepayments). Linking and
// refunding both claim the same token on the rider (`prepay:<paymentId>`), so a
// payment is either tied to a ride or given back, never both.
const RazorpayPrepaySchema = new Schema({
  paymentId: { type: String, required: true, unique: true },
  orderId: String,
  userId: { type: Schema.Types.ObjectId, ref: 'User', index: true },
  amount: Number,                      // ₹ captured
  state: { type: String, enum: ['open', 'linked', 'refunded', 'skipped'], default: 'open' },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  refundedAt: Date,
  leaseAt: Date,
}, { timestamps: true })
RazorpayPrepaySchema.index({ state: 1, createdAt: 1 })

if (process.env.NODE_ENV !== 'production' && mongoose.models.RazorpayPrepay) mongoose.deleteModel('RazorpayPrepay')
export default mongoose.models.RazorpayPrepay || mongoose.model('RazorpayPrepay', RazorpayPrepaySchema)
