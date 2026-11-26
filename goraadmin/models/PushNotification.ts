import mongoose, { Schema } from 'mongoose'
const PushSchema = new Schema({
  title: String,
  message: String,
  target: { type: String, enum: ['all', 'riders', 'drivers', 'specific', 'zone_riders', 'zone_drivers'], default: 'all' },
  targetUserId: String,
  // Zone targets (zone_riders / zone_drivers): the zone, and the accounts it
  // went to, fixed when it is sent (lib/notifications pushToTargets) — the
  // app feeds show it to exactly those accounts.
  zoneId: { type: String, default: '' },
  zoneName: { type: String, default: '' },
  targetUserIds: { type: [String], default: undefined },
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
PushSchema.index({ targetUserIds: 1 }, { sparse: true })
// Dev only: rebuild on hot reload so enum/field additions apply without a
// server restart (same as models/Ride.ts).
if (process.env.NODE_ENV !== 'production' && mongoose.models.PushNotification) mongoose.deleteModel('PushNotification')
export default mongoose.models.PushNotification || mongoose.model('PushNotification', PushSchema)
