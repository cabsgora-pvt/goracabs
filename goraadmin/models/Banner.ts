import mongoose, { Schema } from 'mongoose'
const BannerSchema = new Schema({
  title: String,
  imageUrl: String,
  targetScreen: { type: String, enum: ['home', 'promo', 'splash'], default: 'home' },
  linkUrl: String,
  isActive: { type: Boolean, default: true },
  sortOrder: { type: Number, default: 0 },
  color: { type: String, default: '#1565C0' },
}, { timestamps: true })
export default mongoose.models.Banner || mongoose.model('Banner', BannerSchema)
