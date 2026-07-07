import mongoose, { Schema } from 'mongoose'

// A live SOS alert raised by a rider or driver during a ride.
const SOSAlertSchema = new Schema({
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  triggeredBy: { type: String, enum: ['user', 'driver'], default: 'user' },
  name: String,
  phone: String,
  lat: Number,
  lng: Number,
  address: String,
  status: { type: String, enum: ['active', 'resolved'], default: 'active' },
}, { timestamps: true })

export default mongoose.models.SOSAlert || mongoose.model('SOSAlert', SOSAlertSchema)
