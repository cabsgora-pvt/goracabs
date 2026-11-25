import mongoose, { Schema } from 'mongoose'

// One row per stored upload: who owns it (for /api/files access and account
// deletion), whether it is private, and its size (daily upload quota).
const UploadSchema = new Schema({
  name: { type: String, required: true, unique: true },   // <ms>-<hex>.<ext>
  ownerType: { type: String, enum: ['rider', 'driver', 'admin'], required: true },
  ownerId: { type: String, required: true },
  private: { type: Boolean, default: false },
  purpose: String,                                        // optional hint from the app, e.g. 'kyc', 'face', 'delivery_proof'
  mime: String,
  size: { type: Number, default: 0 },
  gpsStripped: Boolean,
  createdAt: { type: Date, default: Date.now },
}, { versionKey: false })

UploadSchema.index({ ownerType: 1, ownerId: 1, createdAt: -1 })

export default mongoose.models.Upload || mongoose.model('Upload', UploadSchema)
