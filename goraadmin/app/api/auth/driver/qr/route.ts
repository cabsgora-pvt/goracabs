export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// POST /api/auth/driver/qr  body: { qrUrl }  → save the driver's payment QR image
export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)
    const { qrUrl } = await req.json()
    await connectDB()
    await Driver.findByIdAndUpdate(payload.id, { paymentQrUrl: qrUrl || '' })
    return withCors({ success: true, paymentQrUrl: qrUrl || '' })
  } catch (e: any) {
    return withCors({ error: e.message || 'Failed' }, 500)
  }
}
