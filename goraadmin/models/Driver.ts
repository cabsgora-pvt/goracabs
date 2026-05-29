import mongoose, { Schema } from 'mongoose'
const DocumentSchema = new Schema({
  name: String,
  fileUrl: String,
  status: { type: String, enum: ['pending', 'verified', 'rejected'], default: 'pending' },
  expiryDate: String,
})
const DriverSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  status: { type: String, enum: ['pending', 'approved', 'blocked', 'rejected'], default: 'pending' },
  isOnline: { type: Boolean, default: false },
  vehicleNumber: String,
  vehicleModel: String,
  vehicleType: String,
  rating: { type: Number, default: 0 },
  totalRides: { type: Number, default: 0 },
  totalEarnings: { type: Number, default: 0 },
  walletBalance: { type: Number, default: 0 },
  documents: [DocumentSchema],
  fcmToken: String,
  currentLat: Number,
  currentLng: Number,
  fleetOwnerId: { type: Schema.Types.ObjectId, ref: 'FleetOwner' },
}, { timestamps: true })
export default mongoose.models.Driver || mongoose.model('Driver', DriverSchema)
