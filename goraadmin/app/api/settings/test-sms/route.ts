export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { sendOtpSms, generateOtp } from '@/lib/sms'

// Admin-only helper: sends a real OTP SMS using the saved provider config
// so the admin can verify SMS delivery from the settings page.
export async function POST(req: NextRequest) {
  try {
    const { phone } = await req.json()
    if (!phone || String(phone).replace(/\D/g, '').length < 10) {
      return NextResponse.json({ success: false, message: 'Valid 10-digit phone required' }, { status: 400 })
    }
    const otp = generateOtp()
    const result = await sendOtpSms(String(phone), otp)
    return NextResponse.json({ success: result.success, message: result.message, raw: result.raw })
  } catch (e: any) {
    return NextResponse.json({ success: false, message: e?.message || 'Server error' }, { status: 500 })
  }
}
