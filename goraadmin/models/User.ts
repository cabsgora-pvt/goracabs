import mongoose, { Schema } from 'mongoose'
const UserSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  walletBalance: { type: Number, default: 0 },
  // Razorpay payment ids already added by a wallet top-up, checked and pushed in
  // the same update as the credit so one payment is never added twice.
  walletRechargeRefs: { type: [String], default: undefined, select: false },
  totalRides: { type: Number, default: 0 },
  profilePic: String,
  profilePicUrl: String,
  city: String,
  idNumber: String,
  idPhotoUrl: String,
  fcmToken: String,
  referralCode: { type: String, unique: true, sparse: true },
  referredCount: { type: Number, default: 0 },
  referralEarnings: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.User || mongoose.model('User', UserSchema)
