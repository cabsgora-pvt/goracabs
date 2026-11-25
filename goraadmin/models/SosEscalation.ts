import mongoose, { Schema } from 'mongoose'

// Every SOS escalation attempt (lib/sos-escalate): who was texted and how it
// went. Lets the ops team prove an alert went out, and tests check it ran.
const SosEscalationSchema = new Schema({
  alertId: { type: Schema.Types.ObjectId, ref: 'SOSAlert', index: true },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' },
  recipients: [{ phone: String, kind: { type: String, enum: ['ops', 'contact'] }, ok: Boolean, result: String, _id: false }],
  stubbed: { type: Boolean, default: false },
  at: { type: Date, default: Date.now },
}, { versionKey: false })

export default mongoose.models.SosEscalation || mongoose.model('SosEscalation', SosEscalationSchema)
