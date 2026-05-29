export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const { phone } = await req.json()
    if (!phone) return withCors({ error: 'Phone is required' }, 400)
    // Always succeed with OTP 1234 (demo mode)
    console.log(`[Driver OTP] Phone: ${phone} → OTP: 1234`)
    return withCors({ success: true, message: 'OTP sent' })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
