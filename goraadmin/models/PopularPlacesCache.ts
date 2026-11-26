import mongoose, { Schema } from 'mongoose'

// "Popular places near you" (rider home), cached per ~11 km grid cell so a
// city costs a handful of Google Places calls a week, however many riders open
// the app. `places` is the ready-to-send list (photo URLs already resolved).
const PopularPlacesCacheSchema = new Schema({
  cell: { type: String, required: true, unique: true },   // "22.3,70.8"
  places: { type: Array, default: [] },
  fetchedAt: { type: Date, default: Date.now },
  googleStatus: { type: String, default: 'OK' },
  radiusKm: { type: Number, default: 15 },
}, { timestamps: false })

// Drop cells nobody asked for in 30 days.
PopularPlacesCacheSchema.index({ fetchedAt: 1 }, { expireAfterSeconds: 30 * 24 * 3600 })

export default mongoose.models.PopularPlacesCache || mongoose.model('PopularPlacesCache', PopularPlacesCacheSchema)
