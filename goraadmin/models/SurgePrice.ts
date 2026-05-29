import mongoose, { Schema } from 'mongoose'

const SurgePriceSchema = new Schema({
  zoneId: { type: Schema.Types.ObjectId, ref: 'Zone', required: true },
  zoneName: String,
  dayOfWeek: {
    type: String,
    enum: ['all', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'],
    default: 'all',
  },
  startTime: String,  // "08:00"
  endTime: String,    // "10:00"
  surgeMultiplier: { type: Number, default: 1.5 },
  isActive: { type: Boolean, default: true },
  reason: String,     // "Morning rush", "Evening peak", etc.
}, { timestamps: true })

export default mongoose.models.SurgePrice || mongoose.model('SurgePrice', SurgePriceSchema)
