export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { issueOtp } from '@/lib/otp'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const { phone } = await req.json()
    if (!phone || String(phone).replace(/\D/g, '').length < 10) {
      return withCors({ error: 'Valid phone number required' }, 400)
    }

    const result = await issueOtp(String(phone), 'driver')
    if (!result.ok) return withCors({ error: result.error }, result.status)

    return withCors({ success: true, message: 'OTP sent' })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
