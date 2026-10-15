import mongoose, { Schema } from 'mongoose'

const TransactionSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  // cod_remittance: cash-on-delivery the driver took from a receiver and owes
  // the sender. A debit on the driver's wallet, matched by a credit to the
  // sender's — never revenue, never commissioned.
  type: { type: String, enum: ['ride_earning', 'commission', 'recharge', 'withdrawal', 'subscription', 'cod_remittance'], required: true },
  amount: { type: Number, required: true },        // +credit / -debit on driver wallet
  description: String,
  paymentMode: { type: String, enum: ['cash', 'online', 'wallet'], default: 'cash' },
  balanceAfter: Number,
}, { timestamps: true })

export default mongoose.models.Transaction || mongoose.model('Transaction', TransactionSchema)
