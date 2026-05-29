import mongoose, { Schema } from 'mongoose'
const FleetOwnerSchema = new Schema({
  name: String,
  phone: String,
  email: String,
  commissionPercent: { type: Number, default: 10 },
  status: { type: String, enum: ['active', 'blocked'], default: 'active' },
  totalVehicles: { type: Number, default: 0 },
  totalDrivers: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.FleetOwner || mongoose.model('FleetOwner', FleetOwnerSchema)
