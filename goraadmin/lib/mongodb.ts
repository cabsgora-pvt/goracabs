import mongoose from 'mongoose'

const MONGODB_URI = process.env.MONGODB_URI!

if (!MONGODB_URI) throw new Error('MONGODB_URI not defined')

let cached = (global as any).mongoose || { conn: null, promise: null }
;(global as any).mongoose = cached

export async function connectDB() {
  if (cached.conn) return cached.conn
  if (!cached.promise) {
    cached.promise = mongoose.connect(MONGODB_URI, { bufferCommands: false, serverSelectionTimeoutMS: 10_000 })
  }
  try {
    cached.conn = await cached.promise
  } catch (e) {
    // A failed first connect must not stay cached: without this reset every
    // later request awaited the same rejected promise until a process restart.
    cached.promise = null
    cached.conn = null
    throw e
  }
  return cached.conn
}
