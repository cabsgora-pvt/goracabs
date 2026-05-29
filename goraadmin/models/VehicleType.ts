import mongoose, { Schema } from 'mongoose'
const VehicleTypeSchema = new Schema({
  name: { type: String, required: true },
  icon: { type: String, default: '🚗' },
  capacity: { type: Number, default: 4 },
  baseFare: { type: Number, default: 30 },
  perKm: { type: Number, default: 12 },
  perMin: { type: Number, default: 1 },
  minFare: { type: Number, default: 50 },
  isActive: { type: Boolean, default: true },
  sortOrder: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.VehicleType || mongoose.model('VehicleType', VehicleTypeSchema)
