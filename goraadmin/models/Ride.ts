import mongoose, { Schema } from 'mongoose'
const RideSchema = new Schema({
  riderId: { type: Schema.Types.ObjectId, ref: 'User' },
  riderName: String,
  riderPhone: String,
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver' },
  driverName: String,
  driverPhone: String,
  pickupAddress: String,
  dropAddress: String,
  pickupLat: Number,
  pickupLng: Number,
  dropLat: Number,
  dropLng: Number,
  service: { type: String, enum: ['taxi', 'rental', 'outstation', 'delivery', 'hire_driver'], default: 'taxi' },
  vehicleType: String,
  status: { type: String, enum: ['pending', 'accepted', 'arrived', 'ongoing', 'completed', 'cancelled'], default: 'pending' },
  // ── Outstation-only fields (ignored by taxi/rental/delivery) ──
  tripType: { type: String, enum: ['one_way', 'round_trip'], default: 'one_way' },
  cityFrom: String,
  cityTo: String,
  departureAt: Date,
  returnAt: Date,
  numPassengers: { type: Number, default: 1 },
  multiStops: [{ address: String, lat: Number, lng: Number }],
  nightHaltCharge: Number,     // computed at booking
  emptyReturnCharge: Number,   // computed at booking
  // Extended status for outstation: 'at_destination' + 'returning' beyond the standard set
  outstationPhase: { type: String, enum: ['pickup_pending', 'driver_arriving', 'picked_up', 'enroute', 'at_destination', 'returning', 'completed'], default: 'pickup_pending' },
  // Actual km driven (updated by driver location pushes during ride) — used for billing reconciliation
  actualDistance: { type: Number, default: 0 },
  // Toll charges (set by client or admin when known — Directions API doesn't expose them on free tier)
  tollCharge: { type: Number, default: 0 },
  // Night halt confirmed by both parties (one boolean stamps once user/driver confirms)
  nightHaltConfirmed: { type: Boolean, default: false },
  nightHaltConfirmedAt: Date,
  // ── Rental-only fields (ignored by taxi/outstation/delivery) ──
  packageHours: { type: Number, default: 0 },   // included hours in package
  packageKm: { type: Number, default: 0 },       // included km in package
  extraHourRate: { type: Number, default: 0 },
  extraKmRate: { type: Number, default: 0 },
  nightChargeRental: { type: Number, default: 0 },
  actualHours: { type: Number, default: 0 },     // live + final
  actualKm: { type: Number, default: 0 },        // live (accumulated from pings) + final
  rentalStartedAt: Date,
  rentalEndedAt: Date,
  rentalLastLat: Number,                          // for distance accumulation
  rentalLastLng: Number,
  // started → ongoing → extra_time → completed
  rentalPhase: { type: String, enum: ['pending', 'started', 'ongoing', 'extra_time', 'paused', 'completed'], default: 'pending' },
  isWaiting: { type: Boolean, default: false },   // driver halt/wait toggle
  extraHoursCharge: { type: Number, default: 0 },
  extraKmCharge: { type: Number, default: 0 },
  finalFare: { type: Number, default: 0 },        // base + extras, computed at end
  rentalStops: [{ address: String, lat: Number, lng: Number, at: Date }],
  fare: Number,
  tip: { type: Number, default: 0 },
  totalFare: Number,          // fare + tip
  commissionAmount: Number,   // admin profit
  driverEarning: Number,
  commissionPercent: Number,
  distance: Number,            // road distance (km)
  duration: Number,            // road duration (min)
  routePolyline: String,       // encoded polyline (pickup→drop) for map render + replay
  // Fare breakdown (added for fare-breakdown popup)
  fareBreakdown: {
    base: Number,
    perKm: Number,
    perMin: Number,
    minFare: Number,
    distanceKm: Number,
    durationMin: Number,
    distanceCharge: Number,
    timeCharge: Number,
    subtotal: Number,
    surge: Number,
    tax: Number,
    commission: Number,
  },
  paymentMode: { type: String, enum: ['cash', 'wallet', 'online'], default: 'cash' },
  paymentStatus: { type: String, enum: ['pending', 'paid'], default: 'pending' },
  scheduledAt: Date,
  acceptedAt: Date,
  arrivedAt: Date,
  startedAt: Date,
  completedAt: Date,
  cancelledBy: String,
  cancellationReason: String,
  driverRating: Number,
  riderRating: Number,
  riderReview: String,
  driverReview: String,
  rejectedBy: [String],
  otp: String,
  zoneId: { type: Schema.Types.ObjectId, ref: 'Zone' },
}, { timestamps: true })
export default mongoose.models.Ride || mongoose.model('Ride', RideSchema)
