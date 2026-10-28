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
  // ── Multi-stop (in-city A→B→C) ──
  stops: { type: [{ address: String, lat: Number, lng: Number, reachedAt: Date, waitStartedAt: Date, waitMinutes: { type: Number, default: 0 }, done: { type: Boolean, default: false } }], default: undefined },
  currentStopIndex: { type: Number, default: 0 },     // which stop the driver is heading to / waiting at
  isWaitingAtStop: { type: Boolean, default: false },
  waitingChargeTotal: { type: Number, default: 0 },   // accumulated wait charge across stops
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
  // Tolls the driver paid during an outstation trip, one entry per toll, added
  // only through /rides/{id}/toll. The rider pays them to the driver directly at
  // the end of the trip, so they sit OUTSIDE the fare: no commission, no wallet
  // movement, and not part of totalFare (every revenue total sums that field).
  tolls: {
    type: [{
      amount: { type: Number, required: true },   // whole rupees
      at: { type: Date, default: Date.now },
      source: { type: String, enum: ['prompt', 'manual'], default: 'manual' },
      lat: Number,
      lng: Number,
      // Readable address where it was paid, for the bill. '' if unknown.
      place: String,
      // Set by the app per entry, so a retry after a dropped connection cannot
      // add the same toll twice.
      clientRef: String,
      // The rider's complaint about this toll, once, and the ticket it opened.
      reportedAt: Date,
      reportReason: { type: String, enum: ['no_toll', 'wrong_amount', 'other'] },
      reportNote: String,
      ticketId: { type: Schema.Types.ObjectId, ref: 'SupportTicket' },
    }],
    default: undefined,
  },
  // Sum of `tolls`, maintained with it in the same atomic update.
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
  // pending → ongoing → (extra_time | paused) → completed
  // ('started' was in this enum but nothing ever wrote it.)
  rentalPhase: { type: String, enum: ['pending', 'ongoing', 'extra_time', 'paused', 'completed'], default: 'pending' },
  isWaiting: { type: Boolean, default: false },   // driver halt/wait toggle
  extraHoursCharge: { type: Number, default: 0 },
  extraKmCharge: { type: Number, default: 0 },
  finalFare: { type: Number, default: 0 },        // base + extras, computed at end
  rentalStops: [{ address: String, lat: Number, lng: Number, at: Date }],
  // ── Hire-a-driver fields ──
  hireStartAt: Date,
  hireEndAt: Date,
  hireTotalHours: { type: Number, default: 0 },
  hirePerHour: { type: Number, default: 0 },
  transmission: { type: String, enum: ['manual', 'automatic', ''], default: '' },
  hireStartedAt: Date,            // when driver actually started
  hireActualHours: { type: Number, default: 0 },
  hireExtraHours: { type: Number, default: 0 },
  hireExtraCharge: { type: Number, default: 0 },
  hireFinalFare: { type: Number, default: 0 },
  hirePhase: { type: String, enum: ['pending', 'ongoing', 'overtime', 'completed'], default: 'pending' },
  // ── Parcel / Delivery fields ──
  senderName: String,
  senderPhone: String,
  receiverName: String,
  receiverPhone: String,
  itemType: String,
  weightKg: { type: Number, default: 0 },
  parcelPhotos: [String],
  dropOtp: String,                // receiver shows this to driver to confirm handover
  // collected (sender OTP done) → in_transit → delivered
  deliveryPhase: { type: String, enum: ['pending', 'collected', 'in_transit', 'delivered', 'failed', 'returned'], default: 'pending' },
  deliveryDistance: { type: Number, default: 0 },   // km driven during delivery
  deliveryLastLat: Number, deliveryLastLng: Number,
  failReason: String,
  packageSize: { type: String, enum: ['S', 'M', 'L', ''], default: '' },
  isFragile: { type: Boolean, default: false },
  itemValue: { type: Number, default: 0 },     // declared value (for insurance reference)
  codAmount: { type: Number, default: 0 },     // cash-on-delivery the receiver owes the SENDER
  // COD actually taken from the receiver. Zero on a return-to-sender, since the
  // receiver never accepted the parcel. Held separately from codAmount so the
  // amount owed and the amount collected can never be confused at settlement.
  codCollected: { type: Number, default: 0 },
  // Set once the collected COD has been moved from the driver to the sender, so
  // a repeated /complete (retry, double-tap) can never pay the sender twice.
  codSettledAt: Date,
  // Final delivery fare at handover. Mirrors finalFare / hireFinalFare so the
  // settlement path can bill delivery the same way it bills the other services.
  deliveryFinalFare: Number,
  deliveryProofPhoto: String,                  // driver's proof-of-delivery photo URL
  deliverySignature: String,                   // receiver's signature image URL
  deliveredAt: Date,
  // scheduledAt already defined below (shared with other scheduled bookings)
  deliveryStops: { type: [{ address: String, lat: Number, lng: Number, receiverName: String, receiverPhone: String }], default: undefined },
  fare: Number,
  tip: { type: Number, default: 0 },
  totalFare: Number,          // fare + tip
  // Split fare: co-riders each pay a share of `fare` (not tip) from their own
  // wallet. `phone` is stored as the last 10 digits so it matches regardless
  // of how the rider typed it (+91, spaces, dashes).
  splitRequests: {
    type: [{
      phone: String, name: String, share: Number,
      status: { type: String, enum: ['pending', 'paid'], default: 'pending' },
      paidBy: { type: Schema.Types.ObjectId, ref: 'User' },
      paidAt: Date,
    }],
    default: undefined,
  },
  splitCollected: { type: Number, default: 0 }, // sum of paid split shares, credited to the driver already
  splitCommission: { type: Number, default: 0 }, // admin's cut already taken out of splitCollected, kept so /complete's totals stay accurate
  // Rider asked to be matched with a female driver. Best-effort: dispatch tries
  // the female-only pool first and falls back to everyone if nobody is nearby,
  // so this never strands a ride waiting for a driver who isn't there.
  preferFemaleDriver: { type: Boolean, default: false },
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
  // ── Mid-ride face re-check (random, once per ride) ──
  faceVerifyDueAt: Date,                 // when the next poll should demand a check; set lazily on first poll
  faceVerifyTriggered: { type: Boolean, default: false }, // already asked for one this ride — don't ask twice
  cancellationFee: { type: Number, default: 0 },
  // ── Money captured BEFORE a driver was found (outstation pays at booking) ──
  // Recorded at booking from a server-verified source — the rider's own wallet
  // debit row, or a signature-checked Razorpay order — never from a client
  // amount. Exists so a ride the system closes for "No driver found" can give
  // that money back (lib/dispatch.ts → settleNoDriverRefunds).
  prepaidAmount: { type: Number, default: 0 },
  prepaidVia: String,            // 'wallet' | 'online'
  prepaidRef: String,            // WalletTransaction _id, or Razorpay payment id
  // The rider was charged upfront but the payment could not be tied to this
  // ride (old app build, gateway lookup failed). Such a ride is never closed
  // automatically, because the system could not give the money back.
  prepaidUnlinked: { type: Boolean, default: false },
  // Refund bookkeeping for any cancellation (lib/refunds.ts). refundPending is
  // set in the same atomic update that cancels the ride, so a crash before the
  // wallet credit is retried by the next sweep instead of being lost.
  refundPending: { type: Boolean, default: false },
  refundLeaseAt: Date,
  refundedAmount: { type: Number, default: 0 },
  // The status the ride was cancelled FROM (pending / accepted / arrived /
  // ongoing). Decides what lib/refunds.ts gives back.
  cancelledFromStatus: String,
  // Set when a cancelled ride's upfront payment must be refunded by an admin
  // rather than automatically: 'prepay_unlinked' | 'cancelled_mid_trip'.
  refundReview: String,
  driverRating: Number,
  riderRating: Number,
  riderReview: String,
  driverReview: String,
  rejectedBy: [String],
  // ── Offer-based dispatch (Rapido-style) ──
  // Instead of listing a pending ride to every matching driver at once, it is
  // OFFERED to the best-ranked candidate for a short window. On expiry or
  // rejection it escalates to the next. offeredTo=null with offerRound>0 means
  // the ladder is exhausted and the ride falls back to the open pool.
  offeredTo: { type: Schema.Types.ObjectId, ref: 'Driver', default: null },
  offeredAt: Date,
  offerExpiresAt: Date,
  offerRound: { type: Number, default: 0 },   // how many candidates have been tried
  offerEtaMin: Number,                        // ETA quoted to the offered driver
  otp: String,
  zoneId: { type: Schema.Types.ObjectId, ref: 'Zone' },
  // Online payment gating: driver ended an online ride → rider must pay before it completes
  awaitingPayment: { type: Boolean, default: false },
  // ── ETA telemetry (prediction vs reality) ──
  // Stamped at accept, measured at arrived. This is the feedback loop the ETA
  // engine learns from — without it ETA accuracy is unmeasurable.
  predictedEtaMin: Number,        // minutes we promised the rider at accept time
  pickupCrowKm: Number,           // straight-line driver→pickup km at accept (MEASURED)
  etaMinPerKm: Number,            // the learned factor used for that prediction
  etaFactorSource: String,        // which profile tier supplied it, or 'default'
  etaPredictedAt: Date,
  actualPickupMin: Number,        // measured acceptedAt → arrivedAt
  etaErrorMin: Number,            // actual − predicted (positive = we under-promised)
  // The learning signal: real elapsed travel minutes ÷ real crow km. Both terms
  // are observed, so unlike the old observedSpeedKmph this cannot launder a
  // wrong circuity assumption back into the model.
  observedMinPerKm: Number,
  // In-ride chat between rider and driver
  messages: [{
    sender: { type: String, enum: ['user', 'driver'] },
    text: String,
    createdAt: { type: Date, default: Date.now },
  }],
}, { timestamps: true })

// The driver-pending feed runs every few seconds per online driver and was a
// full collection scan. These cover its filter, plus the busy-driver lookup
// that the ETA engine issues on every fare estimate.
RideSchema.index({ status: 1, service: 1, vehicleType: 1, createdAt: -1 })
RideSchema.index({ status: 1, driverId: 1 })
RideSchema.index({ riderId: 1, createdAt: -1 })
// Speed-profile aggregation scans completed rides with usable ETA telemetry.
RideSchema.index({ observedMinPerKm: 1, arrivedAt: -1 })

export default mongoose.models.Ride || mongoose.model('Ride', RideSchema)
