import mongoose, { Schema } from 'mongoose'

// One row per mid-ride identity re-check (or a standalone re-verify after a
// lock). Kept even on a match, so the admin has a full audit trail, not just
// the failures.
const FaceVerificationSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver', required: true, index: true },
  rideId: { type: Schema.Types.ObjectId, ref: 'Ride' }, // null for a standalone re-verify (clearing a lock)
  status: {
    type: String,
    enum: ['pending', 'matched', 'mismatch', 'no_response'],
    default: 'pending',
  },
  photoUrl: String,       // the attempt's captured photo, for the admin to eyeball against faceReferencePhotoUrl
  matchScore: Number,     // cosine similarity vs the stored signature, when a photo was submitted
  triggeredAt: { type: Date, default: Date.now },
  respondedAt: Date,
  deadlineAt: { type: Date, required: true },
  reviewedByAdmin: { type: Boolean, default: false },
}, { timestamps: true })

FaceVerificationSchema.index({ driverId: 1, createdAt: -1 })

export default mongoose.models.FaceVerification || mongoose.model('FaceVerification', FaceVerificationSchema)
