import mongoose, { Schema } from 'mongoose'

// A live SOS alert raised by a rider or driver during a ride.
// status: active (raised) → acknowledged (an admin has seen it and is on it)
// → resolved (closed with a note). "Unresolved" = active + acknowledged.
export const SOS_OPEN_STATUSES = ['active', 'acknowledged']
const SOSAlertSchema = new Schema({
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  triggeredBy: { type: String, enum: ['user', 'driver'], default: 'user' },
  name: String,
  phone: String,
  lat: Number,
  lng: Number,
  address: String,
  status: { type: String, enum: ['active', 'acknowledged', 'resolved'], default: 'active' },
  // Who handled it and when (admin email, or "zone:<email>" from the zone panel).
  acknowledgedAt: Date,
  acknowledgedBy: String,
  resolvedAt: Date,
  resolvedBy: String,
  resolutionNote: String,
}, { timestamps: true })

SOSAlertSchema.index({ status: 1 })
SOSAlertSchema.index({ status: 1, createdAt: -1 })
// Dev only: rebuild on hot reload so enum/field additions apply without a
// server restart (same as models/Ride.ts).
if (process.env.NODE_ENV !== 'production' && mongoose.models.SOSAlert) mongoose.deleteModel('SOSAlert')
export default mongoose.models.SOSAlert || mongoose.model('SOSAlert', SOSAlertSchema)
