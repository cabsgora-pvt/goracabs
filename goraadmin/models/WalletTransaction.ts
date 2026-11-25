import mongoose, { Schema } from 'mongoose'

// One row per wallet movement. balanceAfter is stored so history is auditable.
const WalletTransactionSchema = new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User', index: true },
  type: { type: String, enum: ['credit', 'debit'], required: true },
  amount: { type: Number, required: true },     // always positive ₹
  balanceAfter: { type: Number, default: 0 },
  note: { type: String, default: '' },
  // recharge = user added money, ride = ride payment, admin = manual adjust, refund
  source: { type: String, enum: ['recharge', 'ride', 'admin', 'refund', 'cashback', 'cod'], default: 'recharge' },
  // Razorpay payment id (or other gateway ref) — used for idempotency
  ref: { type: String, default: '', index: true },
}, { timestamps: true })

// Dev only: rebuild on hot reload so enum/field additions apply without a
// server restart (same as models/Ride.ts).
if (process.env.NODE_ENV !== 'production' && mongoose.models.WalletTransaction) mongoose.deleteModel('WalletTransaction')
export default mongoose.models.WalletTransaction || mongoose.model('WalletTransaction', WalletTransactionSchema)
