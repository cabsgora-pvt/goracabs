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
  // true = the amount was taken off the wallet when the driver requested it
  // (approve just marks it paid, reject gives it back). Absent on requests made
  // before holds existed — those are debited at approval instead.
  holdPlaced: { type: Boolean, default: false },
  holdReleased: { type: Boolean, default: false },
  payoutRef: { type: String, default: '' },   // bank UTR / payout reference entered at approval
  processedBy: { type: String, default: '' }, // admin email
  // The saved bank account the payout goes to (Driver.bankAccounts _id, or
  // 'bankDetails' for the registration account), and whether it was added or
  // changed in the 7 days before the request (a takeover signal for the admin).
  accountId: { type: String, default: '' },
  bankChangedRecently: { type: Boolean, default: false },
}, { timestamps: true })
WithdrawalSchema.index({ driverId: 1, createdAt: -1 })
WithdrawalSchema.index({ status: 1, createdAt: -1 })
// Dev only: rebuild on hot reload so enum/field additions apply without a
// server restart (same as models/Ride.ts).
if (process.env.NODE_ENV !== 'production' && mongoose.models.Withdrawal) mongoose.deleteModel('Withdrawal')
export default mongoose.models.Withdrawal || mongoose.model('Withdrawal', WithdrawalSchema)
