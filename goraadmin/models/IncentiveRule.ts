import mongoose, { Schema } from 'mongoose'

// An incentive admin offers drivers — Rapido's "Rain / Long-pickup / Daily /
// Weekly" bonuses are all shapes of this.
//
// The driver app previously rendered mockIncentives: invented targets and
// progress, promising bonuses that did not exist. Progress is now computed
// from the driver's own completed rides in /api/auth/driver/incentives.
const IncentiveRuleSchema = new Schema({
  title: String,
  description: String,

  // What is counted toward the target.
  //   rides    — number of completed rides
  //   earnings — sum of driverEarning (₹)
  metric: { type: String, enum: ['rides', 'earnings'], default: 'rides' },
  target: { type: Number, default: 0 },

  // Rolling window the target must be hit within.
  period: { type: String, enum: ['day', 'week', 'month'], default: 'day' },

  // Optional narrowing. Empty/null means "any".
  service: { type: String, default: '' },          // taxi | rental | outstation | delivery | hire_driver
  vehicleTypeName: { type: String, default: '' },
  zoneId: { type: String, default: '' },
  // Hour-of-day window in IST, inclusive start / exclusive end. Equal values
  // mean the whole day. This is what makes a "Morning Star 6AM–10AM" possible.
  startHour: { type: Number, default: 0 },
  endHour: { type: Number, default: 0 },

  rewardAmount: { type: Number, default: 0 },      // ₹ paid on completion

  isActive: { type: Boolean, default: true },
  validFrom: Date,
  validTo: Date,
}, { timestamps: true })

export default mongoose.models.IncentiveRule || mongoose.model('IncentiveRule', IncentiveRuleSchema)
