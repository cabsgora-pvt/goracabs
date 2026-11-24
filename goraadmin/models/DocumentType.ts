import mongoose, { Schema } from 'mongoose'

// Driver document the admin asks for at registration (dynamic list). Every
// part of how the driver app asks for it is set here by the admin.
const DocumentTypeSchema = new Schema({
  key: { type: String, required: true, unique: true },   // 'dl', 'rc', 'police_verification'
  name: { type: String, required: true },
  // Document type: groups the list in the app and the admin.
  category: { type: String, enum: ['identity', 'vehicle', 'driving', 'other'], default: 'other' },
  description: { type: String, default: '' },             // instructions shown to the driver
  needsNumber: { type: Boolean, default: true },          // false: photo only, no number field
  numberLabel: { type: String, default: 'Document Number' },
  frontLabel: { type: String, default: 'Front side' },
  backLabel: { type: String, default: 'Back side' },
  needsBack: { type: Boolean, default: false },
  needsExpiry: { type: Boolean, default: false },
  required: { type: Boolean, default: true },
  isActive: { type: Boolean, default: true },
  // Vehicle type names this is asked for ('Cab', 'Bike'…). Empty = every driver.
  vehicleTypes: { type: [String], default: [] },
  order: { type: Number, default: 0 },
}, { timestamps: true })

export default mongoose.models.DocumentType || mongoose.model('DocumentType', DocumentTypeSchema)
