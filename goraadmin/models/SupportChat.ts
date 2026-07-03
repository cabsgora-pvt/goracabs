import mongoose, { Schema } from 'mongoose'

const ChatMessageSchema = new Schema({
  sender: { type: String, enum: ['driver', 'admin'], required: true },
  message: String,
  sentAt: { type: Date, default: Date.now },
})

// One persistent support conversation per driver (admin ↔ driver).
const SupportChatSchema = new Schema({
  driverId: { type: Schema.Types.ObjectId, ref: 'Driver', unique: true },
  driverName: String,
  driverPhone: String,
  zoneName: String,
  messages: [ChatMessageSchema],
  lastMessageAt: Date,
  adminUnread: { type: Number, default: 0 },   // unseen by admin
  driverUnread: { type: Number, default: 0 },   // unseen by driver
}, { timestamps: true })

export default mongoose.models.SupportChat || mongoose.model('SupportChat', SupportChatSchema)
