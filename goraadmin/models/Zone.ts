import mongoose, { Schema } from 'mongoose'
const PricingSchema = new Schema({
  vehicleTypeId: { type: Schema.Types.ObjectId, ref: 'VehicleType' },
  vehicleTypeName: String,
  service: { type: String, enum: ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver'] },
  baseFare: Number,
  perKm: Number,
  perMin: Number,
  minFare: Number,
  commissionPercent: { type: Number, default: 20 },
  isActive: { type: Boolean, default: true },
  // Outstation-only extras (ignored for taxi / rental / delivery)
  nightHaltCharge:   { type: Number, default: 0 }, // ₹ per night (round-trip only)
  emptyReturnPercent:{ type: Number, default: 0 }, // % of one-way fare added back for one-way (driver returns empty)
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
  peakZoneRadius: { type: Number, default: 0 },
  peakZoneDuration: { type: Number, default: 0 },
  peakZoneRideCount: { type: Number, default: 0 },
  distancePricePercentage: { type: Number, default: 0 },
  maximumDistance: { type: Number, default: 0 },
  maximumOutstationDistance: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.Zone || mongoose.model('Zone', ZoneSchema)
