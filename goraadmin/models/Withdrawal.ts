import mongoose, { Schema } from 'mongoose'
const WithdrawalSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  driverName: String,
  amount: Number,
  bankName: String,
  accountNumber: String,
  ifscCode: String,
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  processedAt: Date,
  note: String,
}, { timestamps: true })
export default mongoose.models.Withdrawal || mongoose.model('Withdrawal', WithdrawalSchema)
