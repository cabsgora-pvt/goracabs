import mongoose, { Schema } from 'mongoose'
const WithdrawalSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  driverName: String,
  driverPhone: String,       // snapshot for the admin list
  vehicleType: String,       // snapshot
  zoneName: String,          // snapshot
  amount: Number,
  accountHolderName: String,
  bankName: String,
  accountNumber: String,
  ifscCode: String,
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  processedAt: Date,
  note: String,              // rejection reason / admin note
}, { timestamps: true })
export default mongoose.models.Withdrawal || mongoose.model('Withdrawal', WithdrawalSchema)
