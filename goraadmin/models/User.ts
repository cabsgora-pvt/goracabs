import mongoose, { Schema } from 'mongoose'
const UserSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  walletBalance: { type: Number, default: 0 },
  totalRides: { type: Number, default: 0 },
  profilePic: String,
  profilePicUrl: String,
  city: String,
  idNumber: String,
  idPhotoUrl: String,
  fcmToken: String,
}, { timestamps: true })
export default mongoose.models.User || mongoose.model('User', UserSchema)
