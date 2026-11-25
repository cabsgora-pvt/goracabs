import mongoose, { Schema } from 'mongoose'
const AdminSchema = new Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true },
  role: { type: String, default: 'admin' },
  // Bumped on logout / log out everywhere: tokens carry it as `tv`.
  tokenVersion: { type: Number, default: 0 },
  // Re-auth ("sudo") window opened by a correct X-Admin-Password, bound to the
  // session token that sent it (sha256 of the token). lib/admin-password.
  sudoUntil: Date,
  sudoTokenHash: String,
}, { timestamps: true })
export default mongoose.models.Admin || mongoose.model('Admin', AdminSchema)
