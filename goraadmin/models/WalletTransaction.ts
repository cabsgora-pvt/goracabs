import mongoose, { Schema } from 'mongoose'

// One row per wallet movement. balanceAfter is stored so history is auditable.
const WalletTransactionSchema = new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User', index: true },
  type: { type: String, enum: ['credit', 'debit'], required: true },
  amount: { type: Number, required: true },     // always positive ₹
  balanceAfter: { type: Number, default: 0 },
  note: { type: String, default: '' },
  // recharge = user added money, ride = ride payment, admin = manual adjust, refund
  source: { type: String, enum: ['recharge', 'ride', 'admin', 'refund', 'cashback'], default: 'recharge' },
}, { timestamps: true })

export default mongoose.models.WalletTransaction || mongoose.model('WalletTransaction', WalletTransactionSchema)
