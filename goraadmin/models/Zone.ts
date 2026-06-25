import mongoose, { Schema } from 'mongoose'
const PricingSchema = new Schema({
  vehicleTypeId: { type: Schema.Types.ObjectId, ref: 'VehicleType' },
  vehicleTypeName: String,
  service: { type: String, enum: ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver'] },
  baseFare: Number,
  perKm: Number,
  perMin: Number,
  perHour: { type: Number, default: 0 },   // used by hire-a-driver pricing
  hireReturnCharge: { type: Number, default: 0 }, // one-way: flat ₹ for driver's return journey
  perKg: { type: Number, default: 0 },      // used by delivery pricing (₹ per kg of parcel weight)
  minFare: Number,
  commissionPercent: { type: Number, default: 20 },
  isActive: { type: Boolean, default: true },
  // Outstation-only extras (ignored for taxi / rental / delivery)
  nightHaltCharge:   { type: Number, default: 0 }, // ₹ per night (round-trip only)
  emptyReturnPercent:{ type: Number, default: 0 }, // % of one-way fare added back for one-way (driver returns empty)
  // Outstation per-hour (time) charge + separate round-trip rates (fall back to one-way if 0)
  outPerHour:  { type: Number, default: 0 },  // ₹ per hour of travel (one way)
  rtBaseFare:  { type: Number, default: 0 },  // round-trip base fare
  rtPerKm:     { type: Number, default: 0 },  // round-trip per km
  rtPerHour:   { type: Number, default: 0 },  // round-trip per hour
  // Ola-style outstation inclusions
  kmLimitPerDay:  { type: Number, default: 0 }, // included km per day (0 = unlimited / not shown)
  extraKmRate:    { type: Number, default: 0 }, // ₹ per km beyond the included limit
  driverAllowance:{ type: Number, default: 0 }, // ₹ per day driver bata
  gstPercent:     { type: Number, default: 0 }, // GST % applied on fare
})
// Rental packages — multiple per vehicle per zone (e.g. Economy 4hr/40km, Economy 8hr/80km)
const RentalPackageSchema = new Schema({
  vehicleTypeId: { type: Schema.Types.ObjectId, ref: 'VehicleType' },
  vehicleTypeName: String,
  hours: { type: Number, default: 4 },          // included hours
  km: { type: Number, default: 40 },            // included km
  basePrice: { type: Number, default: 0 },      // flat package price
  extraHourRate: { type: Number, default: 0 },  // ₹ per extra hour
  extraKmRate: { type: Number, default: 0 },    // ₹ per extra km
  nightCharge: { type: Number, default: 0 },    // ₹ if booking spans night
  commissionPercent: { type: Number, default: 20 },
  isActive: { type: Boolean, default: true },
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
  rentalPackages: [RentalPackageSchema],
  peakZoneRadius: { type: Number, default: 0 },
  peakZoneDuration: { type: Number, default: 0 },
  peakZoneRideCount: { type: Number, default: 0 },
  distancePricePercentage: { type: Number, default: 0 },
  maximumDistance: { type: Number, default: 0 },
  maximumOutstationDistance: { type: Number, default: 0 },
}, { timestamps: true })
export default mongoose.models.Zone || mongoose.model('Zone', ZoneSchema)
