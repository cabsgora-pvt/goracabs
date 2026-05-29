import mongoose, { Schema } from 'mongoose'

const TransactionSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  type: { type: String, enum: ['ride_earning', 'commission', 'recharge', 'withdrawal'], required: true },
  amount: { type: Number, required: true },        // +credit / -debit on driver wallet
  description: String,
  paymentMode: { type: String, enum: ['cash', 'online', 'wallet'], default: 'cash' },
  balanceAfter: Number,
}, { timestamps: true })

export default mongoose.models.Transaction || mongoose.model('Transaction', TransactionSchema)
