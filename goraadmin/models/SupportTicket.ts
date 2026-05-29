import mongoose, { Schema } from 'mongoose'
const MessageSchema = new Schema({
  sender: String,
  message: String,
  sentAt: { type: Date, default: Date.now },
})
const TicketSchema = new Schema({
  userId: { type: Schema.Types.ObjectId, ref: 'User' },
  userName: String,
  subject: String,
  category: String,
  priority: { type: String, enum: ['low', 'medium', 'high'], default: 'medium' },
  status: { type: String, enum: ['open', 'in_progress', 'resolved', 'closed'], default: 'open' },
  messages: [MessageSchema],
}, { timestamps: true })
export default mongoose.models.SupportTicket || mongoose.model('SupportTicket', TicketSchema)
