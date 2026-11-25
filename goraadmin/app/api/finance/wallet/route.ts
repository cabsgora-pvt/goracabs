import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { getSettings, invalidateSettingsCache } from '@/lib/settings'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { maskSettings, unmaskSettings } from '@/lib/settings-secrets'

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    let settings: any = await Settings.findOne({ key: 'global' }).lean()
    if (!settings) settings = getSettings()
    return NextResponse.json(maskSettings(settings?.payment || {}, 'payment'))
  } catch {
    return NextResponse.json({ error: 'Failed to read wallet settings' }, { status: 500 })
  }
}

// Writes the whole payment block (incl. Razorpay secrets): admin + password.
export async function PUT(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await connectDB()
    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return NextResponse.json({ error: 'Invalid settings' }, { status: 400 })
    }
    const current: any = await Settings.findOne({ key: 'global' }).select('payment').lean()
    unmaskSettings(body, current?.payment || {}, 'payment')
    const settings = await Settings.findOneAndUpdate(
      { key: 'global' },
      { $set: { payment: body } },
      { upsert: true, new: true }
    ).lean()
    invalidateSettingsCache()
    return NextResponse.json(maskSettings((settings as any).payment, 'payment'))
  } catch {
    return NextResponse.json({ error: 'Failed to save wallet settings' }, { status: 500 })
  }
}
