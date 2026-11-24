import mongoose, { Schema } from 'mongoose'

// A request from a rider or driver that the admin must decide:
//   delete       — delete my account (with a reason)
//   zone_change  — driver asks to move to another zone
const AccountRequestSchema = new Schema({
  userType: { type: String, enum: ['rider', 'driver'], required: true },
  userId: { type: Schema.Types.ObjectId, required: true, index: true },
  name: String,
  phone: String,
  kind: { type: String, enum: ['delete', 'zone_change'], required: true },
  reason: String,
  note: String,
  toZoneId: String,
  toZoneName: String,
  fromZoneId: String,
  fromZoneName: String,
  status: { type: String, enum: ['pending', 'approved', 'rejected', 'cancelled'], default: 'pending', index: true },
  adminNote: String,
  handledAt: Date,
  handledBy: String,
}, { timestamps: true })

export default mongoose.models.AccountRequest || mongoose.model('AccountRequest', AccountRequestSchema)
