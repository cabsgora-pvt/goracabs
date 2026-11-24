import mongoose, { Schema } from 'mongoose'
const DocumentSchema = new Schema({
  name: String,
  type: String,          // 'aadhaar' | 'pan' | 'rc' | 'insurance' | 'dl'
  number: String,        // document number entered by the driver
  fileUrl: String,       // front image (kept for backward compatibility)
  frontUrl: String,      // front image
  backUrl: String,       // back image (aadhaar / insurance)
  status: { type: String, enum: ['pending', 'verified', 'rejected'], default: 'pending' },
  expiryDate: String,    // insurance expiry (yyyy-MM-dd)
  uploadedAt: Date,
})
const DriverSchema = new Schema({
  name: String,
  phone: { type: String, unique: true },
  email: String,
  profilePicUrl: String,
  // ── Face verification (identity re-check mid-ride) ──
  // Embedding captured once at registration (MobileFaceNet-style vector from
  // the driver app's on-device model). Later verification attempts compare
  // their own embedding against this one server-side — never trusting the
  // device's own "matched" claim.
  faceSignature: { type: [Number], default: undefined },
  faceReferencePhotoUrl: String,       // the frontal shot the signature was derived from
  faceSignatureSavedAt: Date,
  // Set when a mid-ride check comes back mismatched or unanswered. Blocks the
  // driver from going online again until they pass a fresh check.
  faceVerificationRequired: { type: Boolean, default: false },
  faceVerificationReason: String,      // 'mismatch' | 'no_response'
  // Set by an admin (POST /api/drivers/{id}/face-reset) to let an already
  // submitted/approved driver capture a new reference face once. Cleared by
  // auth/driver/face-signature when it is used.
  faceResetAllowed: { type: Boolean, default: false },
  // Short per-driver lease held by POST /rides/{id}/accept (lib/dispatch).
  acceptLeaseUntil: { type: Date, default: null },
  // Self-declared at registration, optional. Undeclared (undefined) drivers are
  // simply not matched when a rider asks for a female driver — never blocked
  // from other rides.
  gender: { type: String, enum: ['female', 'male', 'other'] },
  status: { type: String, enum: ['pending', 'approved', 'blocked', 'rejected', 'deleted'], default: 'pending' },
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
  // Zone: set by the admin (manual), or followed from the driver's location
  // when zoneAuto is on. Every change is kept in zoneHistory.
  zoneAuto: { type: Boolean, default: false },
  zoneHistory: [{ from: String, fromName: String, to: String, toName: String, by: String, at: Date, _id: false }],
  // Automatic zone follow (lib/zone-auto): the zone the driver's fixes have
  // been inside since `firstAt`. Switched only after a second fix ≥ 60 s later.
  zoneAutoCandidate: { zoneId: String, firstAt: Date },
  // Ride preference types (admin-defined, e.g. 'pet_friendly') this driver offers.
  ridePreferences: { type: [String], default: [] },
  isOnline: { type: Boolean, default: false },
  // Driver opts in to receive intercity outstation requests (off by default — taxi only)
  acceptsOutstation: { type: Boolean, default: false },
  // Driver opts in to receive hourly rental package requests
  acceptsRental: { type: Boolean, default: false },
  // Driver opts in to receive hire-a-driver requests (drive customer's own car)
  acceptsHireDriver: { type: Boolean, default: false },
  // Driver opts in to receive parcel/delivery requests
  acceptsDelivery: { type: Boolean, default: false },
  // Admin gates which services a driver is ALLOWED to enable. If false, the
  // option is hidden in the driver's Preferences and forced off.
  allowTaxi: { type: Boolean, default: true },
  allowRental: { type: Boolean, default: true },
  allowOutstation: { type: Boolean, default: true },
  allowHireDriver: { type: Boolean, default: true },
  allowDelivery: { type: Boolean, default: true },
  vehicleNumber: String,
  vehicleModel: String,
  vehicleType: String,
  rating: { type: Number, default: 0 },
  totalRides: { type: Number, default: 0 },
  totalEarnings: { type: Number, default: 0 },
  walletBalance: { type: Number, default: 0 },
  // Razorpay payment ids already credited by a wallet recharge. Checked and
  // pushed in the same update as the credit, so one payment is never added twice.
  walletRechargeRefs: { type: [String], default: undefined, select: false },
  // ── Referral ──
  referralCode: { type: String, index: true },
  referredBy: { type: String, default: '' },      // code the driver signed up with
  referredCount: { type: Number, default: 0 },     // how many drivers used this driver's code
  referralEarnings: { type: Number, default: 0 },  // total ₹ earned from referrals
  // Referral rewards are paid once, when an admin approves the referred driver
  // (drivers/{id}/approve), claimed atomically on this flag.
  referralRewardPaid: { type: Boolean, default: false },
  // Driver's own payment/UPI QR image (shown to riders for direct payment)
  paymentQrUrl: { type: String, default: '' },
  // Sequential serial for the Gora Captain ID card (assigned lazily)
  serialNo: { type: Number },
  // ── Subscription (Rapido-style pass; overrides ride commission while active) ──
  subscriptionActive: { type: Boolean, default: false },
  subscriptionPlanId: { type: Schema.Types.ObjectId, ref: 'SubscriptionPlan' },
  subscriptionPlanName: { type: String, default: '' },
  subscriptionStartedAt: Date,
  subscriptionExpiresAt: Date,
  subscriptionCommissionPercent: { type: Number, default: 0 }, // commission while subscribed (usually 0)
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
  // Multiple saved bank accounts for withdrawals (driver adds/selects via radio)
  bankAccounts: {
    type: [{
      accountHolderName: String,
      bankName: String,
      accountNumber: String,
      ifscCode: String,
    }],
    default: [],
  },
}, { timestamps: true })
// Dev only: rebuild the model on hot reload so newly added fields are not
// stripped by the stale cached schema (same as models/Ride.ts).
// Dispatch / admin-list indexes (additive). Nearby-driver lookup filters on
// status + isOnline + vehicle type and orders by freshest location.
DriverSchema.index({ status: 1, isOnline: 1, selectedVehicleTypeName: 1, locationUpdatedAt: -1 })
DriverSchema.index({ zoneId: 1 })
DriverSchema.index({ status: 1, createdAt: -1 })
if (process.env.NODE_ENV !== 'production' && mongoose.models.Driver) mongoose.deleteModel('Driver')
export default mongoose.models.Driver || mongoose.model('Driver', DriverSchema)
