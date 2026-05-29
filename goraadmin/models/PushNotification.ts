import mongoose, { Schema } from 'mongoose'
const PushSchema = new Schema({
  title: String,
  message: String,
  target: { type: String, enum: ['all', 'riders', 'drivers', 'specific'], default: 'all' },
  targetUserId: String,
  sentAt: { type: Date, default: Date.now },
  deliveredCount: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.PushNotification || mongoose.model('PushNotification', PushSchema)
