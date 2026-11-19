import mongoose, { Schema } from 'mongoose'

// Named sequence, incremented atomically (invoice numbers).
const CounterSchema = new Schema({ _id: String, seq: { type: Number, default: 0 } })

export default mongoose.models.Counter || mongoose.model('Counter', CounterSchema)

export async function nextSeq(name: string): Promise<number> {
  const Counter = mongoose.models.Counter
  const c: any = await Counter.findOneAndUpdate({ _id: name }, { $inc: { seq: 1 } }, { new: true, upsert: true }).lean()
  return c.seq
}
