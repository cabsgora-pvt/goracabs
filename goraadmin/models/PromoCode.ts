import mongoose, { Schema } from 'mongoose'
const PromoSchema = new Schema({
  code: { type: String, required: true, unique: true, uppercase: true },
  type: { type: String, enum: ['percent', 'flat'], default: 'percent' },
  value: Number,
  minOrderAmount: Number,
  maxDiscount: Number,
  maxUses: Number,
  usedCount: { type: Number, default: 0 },
  expiryDate: Date,
  isActive: { type: Boolean, default: true },
}, { timestamps: true })
export default mongoose.models.PromoCode || mongoose.model('PromoCode', PromoSchema)
