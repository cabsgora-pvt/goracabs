import mongoose, { Schema } from 'mongoose'

const TransactionSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  // cod_remittance: cash-on-delivery the driver took from a receiver and owes
  // the sender. A debit on the driver's wallet, matched by a credit to the
  // sender's — never revenue, never commissioned.
  // withdrawal_hold: money set aside when the driver REQUESTS a payout (the
  // wallet drops then); withdrawal_released: that hold given back on reject.
  // 'withdrawal' remains for legacy requests that had no hold (debited at
  // approval). admin_credit / admin_debit: manual adjustments by an admin.
  type: { type: String, enum: ['ride_earning', 'commission', 'recharge', 'withdrawal', 'subscription', 'cod_remittance', 'withdrawal_hold', 'withdrawal_released', 'admin_credit', 'admin_debit', 'split_reversal'], required: true },
  amount: { type: Number, required: true },        // +credit / -debit on driver wallet
  description: String,
  paymentMode: { type: String, enum: ['cash', 'online', 'wallet'], default: 'cash' },
  balanceAfter: Number,
}, { timestamps: true })

TransactionSchema.index({ driverId: 1, createdAt: -1 })
// Dev only: rebuild on hot reload so enum/field additions apply without a
// server restart (same as models/Ride.ts).
if (process.env.NODE_ENV !== 'production' && mongoose.models.Transaction) mongoose.deleteModel('Transaction')
export default mongoose.models.Transaction || mongoose.model('Transaction', TransactionSchema)
