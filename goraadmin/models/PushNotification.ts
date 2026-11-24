import mongoose, { Schema } from 'mongoose'
const PushSchema = new Schema({
  title: String,
  message: String,
  target: { type: String, enum: ['all', 'riders', 'drivers', 'specific'], default: 'all' },
  targetUserId: String,
  imageUrl: String,
  // 'scheduled' waits for scheduledAt (lib/notifications.ts sends it then);
  // 'cancelled' was a scheduled one the admin called off. Rows written before
  // scheduling existed have no status and count as sent.
  status: { type: String, enum: ['sent', 'scheduled', 'cancelled'], default: 'sent', index: true },
  scheduledAt: { type: Date, default: null },
  sentAt: { type: Date, default: Date.now },
  deliveredCount: { type: Number, default: 0 },
}, { timestamps: true })
PushSchema.index({ status: 1, scheduledAt: 1 })
export default mongoose.models.PushNotification || mongoose.model('PushNotification', PushSchema)
