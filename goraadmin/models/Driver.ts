import mongoose, { Schema } from 'mongoose'
const DocumentSchema = new Schema({
  name: String,
  fileUrl: String,
  status: { type: String, enum: ['pending', 'verified', 'rejected'], default: 'pending' },
  expiryDate: String,
  uploadedAt: Date,
})
const DriverSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  profilePicUrl: String,
  status: { type: String, enum: ['pending', 'approved', 'blocked', 'rejected'], default: 'pending' },
  isOnline: { type: Boolean, default: false },
  // Driver opts in to receive intercity outstation requests (off by default — taxi only)
  acceptsOutstation: { type: Boolean, default: false },
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
  currentHeading: { type: Number, default: 0 },   // 0-360, used to rotate driver marker on map
  locationUpdatedAt: Date,                          // last time location was pushed
  fleetOwnerId: { type: Schema.Types.ObjectId, ref: 'FleetOwner' },
  // Registration fields
  state: String,
  zoneId: String,
  zoneName: String,
  registrationStep: { type: String, default: 'otp' },
  rejectionReason: String,
  selectedVehicleTypeId: String,
  selectedVehicleTypeName: String,
  vehicleRegistrationNumber: String,
  bankDetails: {
    accountHolderName: String,
    bankName: String,
    branch: String,
    accountNumber: String,
    ifscCode: String,
    accountType: { type: String, enum: ['savings', 'current'], default: 'savings' },
  },
}, { timestamps: true })
export default mongoose.models.Driver || mongoose.model('Driver', DriverSchema)
