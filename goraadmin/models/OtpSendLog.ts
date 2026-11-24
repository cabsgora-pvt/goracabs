import mongoose, { Schema } from 'mongoose'

// One row per OTP send attempt, kept 24h (TTL). Used to cap sends per phone and
// per IP per day — the Otp doc itself is replaced on every send and expires in
// 5 minutes, so it cannot carry a daily count.
const OtpSendLogSchema = new Schema({
  phone: { type: String, required: true },
  role: { type: String, enum: ['user', 'driver'], default: 'user' },
  ip: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
})

OtpSendLogSchema.index({ phone: 1, createdAt: -1 })
OtpSendLogSchema.index({ ip: 1, createdAt: -1 })
OtpSendLogSchema.index({ createdAt: 1 }, { expireAfterSeconds: 24 * 3600 })

export default mongoose.models.OtpSendLog || mongoose.model('OtpSendLog', OtpSendLogSchema)
