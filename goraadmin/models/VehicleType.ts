import mongoose, { Schema } from 'mongoose'
const VehicleTypeSchema = new Schema({
  name: { type: String, required: true },
  imageUrl: { type: String, default: '' },
  capacity: { type: Number, default: 4 },
  baseFare: { type: Number, default: 30 },
  perKm: { type: Number, default: 12 },
  perMin: { type: Number, default: 1 },
  minFare: { type: Number, default: 50 },
  baseDistance: { type: Number, default: 2 },
  waitingCharge: { type: Number, default: 1 },
  isAcceptShareRide: { type: Boolean, default: false },
  services: { type: [String], default: ['taxi'] }, // taxi, rental, outstation, parcel, hire_driver
  // Category + tier (lib/vehicle-tiers): "cab" with rank 1 Cab, 2 Prime Sedan,
  // 3 Prime SUV. Empty / unset → inferred from the name.
  category: { type: String, default: '' },
  rank: { type: Number, default: null },
  // One line under the name in the rider app ("Top-rated drivers").
  tagline: { type: String, default: '' },
  // What a vehicle must meet for this type (checked at driver registration).
  requirements: {
    minModelYear: { type: Number, default: null },
    minDriverRating: { type: Number, default: null },
    allowedModels: { type: [String], default: undefined },
    note: { type: String, default: '' },
  },
  isActive: { type: Boolean, default: true },
  sortOrder: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.VehicleType || mongoose.model('VehicleType', VehicleTypeSchema)
