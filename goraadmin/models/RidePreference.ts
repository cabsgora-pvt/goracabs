import mongoose, { Schema } from 'mongoose'

// A ride preference the admin offers (e.g. "Pet friendly", "Extra luggage").
// Riders can ask for it when booking; drivers say which ones they offer.
const RidePreferenceSchema = new Schema({
  key: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  description: String,
  icon: { type: String, default: 'star' },  // a Material icon key the apps understand
  services: { type: [String], default: ['taxi', 'rental', 'outstation'] },
  isActive: { type: Boolean, default: true },
  order: { type: Number, default: 0 },
}, { timestamps: true })

export default mongoose.models.RidePreference || mongoose.model('RidePreference', RidePreferenceSchema)
