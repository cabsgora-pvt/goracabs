import mongoose, { Schema } from 'mongoose'

// Stores a single active OTP per phone+role. The OTP itself is bcrypt-hashed
// (never stored in plain text). Records auto-expire via a TTL index.
const OtpSchema = new Schema(
  {
    phone: { type: String, required: true, index: true },
    role: { type: String, enum: ['user', 'driver'], default: 'user' },
    otpHash: { type: String, required: true },
    attempts: { type: Number, default: 0 },
    lastSentAt: { type: Date },
    expiresAt: { type: Date, required: true },
  },
  { timestamps: true }
)

// One live OTP per (phone, role)
OtpSchema.index({ phone: 1, role: 1 }, { unique: true })
// TTL: Mongo removes the doc once expiresAt passes
OtpSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 })

export default mongoose.models.Otp || mongoose.model('Otp', OtpSchema)
