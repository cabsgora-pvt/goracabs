export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { issueOtp } from '@/lib/otp'
import { normalizePhone } from '@/lib/phone'
import { rateLimitAsync, clientIp } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    // Burst limit per IP (Mongo-backed, survives restarts); daily per-IP / per-phone caps live in issueOtp.
    if (!(await rateLimitAsync(req, 'user-send-otp', 5, 10 * 60_000))) {
      return withCors({ error: 'Too many OTP requests. Try again in a few minutes.' }, 429)
    }
    const body = await req.json().catch(() => null)
    const phone = normalizePhone(body?.phone)
    if (!phone) return withCors({ error: 'Valid 10-digit mobile number required' }, 400)

    const result = await issueOtp(phone, 'user', clientIp(req))
    if (!result.ok) return withCors({ error: result.error }, result.status)

    return withCors({ success: true, message: 'OTP sent' })
  } catch {
    return withCors({ error: 'Failed to send OTP' }, 500)
  }
}
