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
  extraConfig: { type: Schema.Types.Mixed, default: {} },
}, { timestamps: true })
export default mongoose.models.ServiceConfig || mongoose.model('ServiceConfig', ServiceConfigSchema)
