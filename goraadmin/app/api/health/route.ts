export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'

// Liveness + DB check for uptime monitors / the deploy script. Public, and
// deliberately says nothing beyond up/down (no versions, hosts or errors).
export async function GET() {
  const started = Date.now()
  try {
    await Promise.race([
      (async () => {
        await connectDB()
        await mongoose.connection.db!.admin().command({ ping: 1 })
      })(),
      new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), 5000)),
    ])
    return NextResponse.json({ ok: true, db: 'up', ms: Date.now() - started }, { headers: { 'Cache-Control': 'no-store' } })
  } catch {
    return NextResponse.json({ ok: false, db: 'down' }, { status: 503, headers: { 'Cache-Control': 'no-store' } })
  }
}
