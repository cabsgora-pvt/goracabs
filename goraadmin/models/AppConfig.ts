import mongoose, { Schema } from 'mongoose'

// Single config document per app ("user" / "driver"). Holds all the content the
// app used to hardcode, so admins can manage it from the dashboard.
const BannerSchema = new Schema({
  title: String, subtitle: String, imageUrl: String, color: { type: String, default: '#1C2656' }, link: String,
  isActive: { type: Boolean, default: true }, sortOrder: { type: Number, default: 0 },
}, { _id: false })

const OfferSchema = new Schema({
  title: String, desc: String, imageUrl: String, isActive: { type: Boolean, default: true },
}, { _id: false })

const CouponSchema = new Schema({
  code: String,
  discountType: { type: String, enum: ['flat', 'percent'], default: 'flat' },
  value: { type: Number, default: 0 },        // ₹ for flat, % for percent
  maxDiscount: { type: Number, default: 0 },  // cap for percent (0 = no cap)
  minFare: { type: Number, default: 0 },      // min fare to apply
  service: { type: String, default: 'all' },  // all | taxi | outstation | rental | hire_driver | delivery
  desc: String,
  isActive: { type: Boolean, default: true },
  expiry: Date,
}, { _id: false })

const PlaceSchema = new Schema({
  name: String, address: String, lat: Number, lng: Number,
}, { _id: false })

const FaqSchema = new Schema({ q: String, a: String }, { _id: false })

const WhyUsSchema = new Schema({ icon: String, title: String, desc: String }, { _id: false })

const AppConfigSchema = new Schema({
  app: { type: String, enum: ['user', 'driver'], default: 'user', unique: true },
  banners: { type: [BannerSchema], default: [] },
  offers: { type: [OfferSchema], default: [] },
  coupons: { type: [CouponSchema], default: [] },
  places: { type: [PlaceSchema], default: [] },
  faqs: { type: [FaqSchema], default: [] },
  whyChooseUs: { type: [WhyUsSchema], default: [] },
  support: {
    phone: { type: String, default: '' },
    email: { type: String, default: '' },
    whatsapp: { type: String, default: '' },
    address: { type: String, default: '' },
  },
  referral: {
    rewardAmount: { type: Number, default: 100 },
    message: { type: String, default: 'Invite friends and earn rewards' },
  },
  version: {
    latestVersion: { type: String, default: '1.0.0' },
    minVersion: { type: String, default: '1.0.0' },
    forceUpdate: { type: Boolean, default: false },
    message: { type: String, default: '' },
  },
}, { timestamps: true })

export default mongoose.models.AppConfig || mongoose.model('AppConfig', AppConfigSchema)
