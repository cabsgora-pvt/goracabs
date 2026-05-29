import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'

// Default OTP for all numbers (development mode)
const DEFAULT_OTP = '1234'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const { phone } = await req.json()
    if (!phone || phone.length < 10) {
      return withCors({ error: 'Valid phone number required' }, 400)
    }
    // In production: send real SMS via Twilio/MSG91
    // For now: always accept DEFAULT_OTP
    console.log(`[OTP] Phone: ${phone} → OTP: ${DEFAULT_OTP}`)
    return withCors({ success: true, message: `OTP sent to ${phone}` })
  } catch {
    return withCors({ error: 'Failed to send OTP' }, 500)
  }
}
