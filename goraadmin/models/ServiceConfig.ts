import mongoose, { Schema } from 'mongoose'
const ServiceConfigSchema = new Schema({
  service: { type: String, unique: true, enum: ['taxi', 'rental', 'outstation', 'delivery', 'goods'] },
  isActive: { type: Boolean, default: true },
  baseFare: Number,
  perKm: Number,
  perMin: Number,
  minFare: Number,
  cancellationFee: Number,
  driverCommissionPercent: Number,
  nightSurchargePercent: Number,
  baseDistance: { type: Number, default: 2 },
  waitingCharge: { type: Number, default: 1 },
  priceType: { type: String, enum: ['ride_now', 'ride_later', 'both'], default: 'both' },
  outstationBaseFare: { type: Number, default: 0 },
  outstationBaseDistance: { type: Number, default: 0 },
  outstationPricePerTime: { type: Number, default: 0 },
  outstationPricePerDistance: { type: Number, default: 0 },
  extraConfig: { type: Schema.Types.Mixed, default: {} },
}, { timestamps: true })
export default mongoose.models.ServiceConfig || mongoose.model('ServiceConfig', ServiceConfigSchema)
