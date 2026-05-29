import mongoose, { Schema } from 'mongoose'
const FAQSchema = new Schema({
  question: String,
  answer: String,
  category: { type: String, enum: ['rider', 'driver', 'payment', 'general'], default: 'general' },
  isActive: { type: Boolean, default: true },
  sortOrder: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.FAQ || mongoose.model('FAQ', FAQSchema)
