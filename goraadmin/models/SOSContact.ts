import mongoose, { Schema } from 'mongoose'
const SOSSchema = new Schema({
  name: String,
  phone: String,
  relation: String,
  addedBy: { type: String, enum: ['admin', 'driver', 'user'], default: 'admin' },
  isActive: { type: Boolean, default: true },
}, { timestamps: true })
export default mongoose.models.SOSContact || mongoose.model('SOSContact', SOSSchema)
