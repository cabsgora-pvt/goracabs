import mongoose, { Schema } from 'mongoose'
const PricingSchema = new Schema({
  vehicleTypeId: { type: Schema.Types.ObjectId, ref: 'VehicleType' },
  vehicleTypeName: String,
  service: { type: String, enum: ['taxi', 'rental', 'outstation', 'delivery'] },
  baseFare: Number,
  perKm: Number,
  perMin: Number,
  minFare: Number,
})
const ZoneSchema = new Schema({
  name: String,
  city: String,
  type: { type: String, enum: ['city','airport','outskirts','industrial','ithub'], default: 'city' },
  isActive: { type: Boolean, default: true },
  polygonPath: [{ lat: Number, lng: Number }],
  centerLat: { type: Number, default: 23.0225 },
  centerLng: { type: Number, default: 72.5714 },
  pricing: [PricingSchema],
}, { timestamps: true })
export default mongoose.models.Zone || mongoose.model('Zone', ZoneSchema)
