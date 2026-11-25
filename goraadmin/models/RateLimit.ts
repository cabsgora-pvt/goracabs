import mongoose, { Schema } from 'mongoose'

// Fixed-window counters for lib/rate-limit (key = "<name>:<subject>:<window#>").
// Stored so limits and login lockouts survive a restart; the TTL index drops a
// window once it has ended.
const RateLimitSchema = new Schema({
  _id: String,
  count: { type: Number, default: 0 },
  expiresAt: { type: Date, required: true },
}, { versionKey: false })

RateLimitSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 })

export default mongoose.models.RateLimit || mongoose.model('RateLimit', RateLimitSchema)
