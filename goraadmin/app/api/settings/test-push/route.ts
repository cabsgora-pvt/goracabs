export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { guardAdmin } from '@/lib/admin-guard'
import { verifyPushCredentials } from '@/lib/push'

// POST { token? } → verify the Firebase service account really works.
//
// The admin's "Test Notification" button was a 1.5 s setTimeout that always
// reported success, so the one control an operator would use to confirm push
// was live told them it was regardless. This does a real OAuth exchange against
// Google, and delivers an actual notification when given a device token.
export async function POST(req: NextRequest) {
  const denied = guardAdmin(req)
  if (denied) return denied

  const body = await req.json().catch(() => ({} as any))
  const token = typeof body?.token === 'string' && body.token.trim() ? body.token.trim() : undefined

  const result = await verifyPushCredentials(token)
  return NextResponse.json(result, { status: result.ok ? 200 : 400 })
}
