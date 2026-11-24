import mongoose, { Schema } from 'mongoose'
const UserSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  status: { type: String, enum: ['active', 'blocked', 'deleted'], default: 'active' },
  // Account hold: the person can still sign in and see their account, but a
  // held driver cannot go online or take rides, and a held rider cannot book.
  // kind 'face' (wrong face scan), 'wallet' (wallet mis-transaction), 'manual'.
  accountHold: {
    active: { type: Boolean, default: false },
    kind: { type: String, enum: ['face', 'wallet', 'manual', 'other'], default: 'manual' },
    reason: String,
    at: Date,
    by: String,
  },
  deletedAt: Date,
  walletBalance: { type: Number, default: 0 },
  // Razorpay payment ids already added by a wallet top-up, checked and pushed in
  // the same update as the credit so one payment is never added twice.
  walletRechargeRefs: { type: [String], default: undefined, select: false },
  totalRides: { type: Number, default: 0 },
  profilePic: String,
  profilePicUrl: String,
  city: String,
  gender: { type: String, enum: ['female', 'male', 'other'] },
  idNumber: String,
  idPhotoUrl: String,
  fcmToken: String,
  referralCode: { type: String, unique: true, sparse: true },
  referredCount: { type: Number, default: 0 },
  referralEarnings: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.User || mongoose.model('User', UserSchema)
