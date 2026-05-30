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
  service: { type: String, enum: ['taxi', 'rental', 'outstation', 'delivery'], default: 'taxi' },
  vehicleType: String,
  status: { type: String, enum: ['pending', 'accepted', 'arrived', 'ongoing', 'completed', 'cancelled'], default: 'pending' },
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
