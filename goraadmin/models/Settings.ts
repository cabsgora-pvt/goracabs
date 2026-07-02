import mongoose, { Schema } from 'mongoose'
const SettingsSchema = new Schema({
  key: { type: String, unique: true, default: 'global' },
  general: { type: Schema.Types.Mixed, default: {} },
  payment: { type: Schema.Types.Mixed, default: {} },
  maps: { type: Schema.Types.Mixed, default: {} },
  sms: { type: Schema.Types.Mixed, default: {} },
  mail: { type: Schema.Types.Mixed, default: {} },
  firebase: { type: Schema.Types.Mixed, default: {} },
  services: { type: Schema.Types.Mixed, default: {} },
  // Driver-app rules: { walletBlockEnabled, maxNegativeWallet }
  driverApp: { type: Schema.Types.Mixed, default: {} },
}, { timestamps: true })
export default mongoose.models.Settings || mongoose.model('Settings', SettingsSchema)
