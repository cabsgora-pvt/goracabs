import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { getSettings, invalidateSettingsCache } from '@/lib/settings'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { maskSettings, unmaskSettings } from '@/lib/settings-secrets'

// Secrets are masked (bullets + last 4) on the way out; a masked value posted
// back is replaced with the stored one (lib/settings-secrets).
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    let settings: any = await Settings.findOne({ key: 'global' }).lean()
    if (!settings) {
      // First run: seed Mongo from the legacy JSON file.
      const fallback = getSettings()
      const created: any = await Settings.create({ key: 'global', ...fallback })
      settings = created.toObject ? created.toObject() : created
    }
    return NextResponse.json(maskSettings(settings))
  } catch {
    return NextResponse.json({ error: 'Failed to read settings' }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    // Changing settings needs the admin's password again (panel prompts for it).
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await connectDB()
    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return NextResponse.json({ error: 'Invalid settings' }, { status: 400 })
    }
    // Franchise mode has its own confirmed switch (settings/franchise); a page
    // saving every setting it loaded must not put back an old value of it.
    const { franchise: _franchise, _id: _i, createdAt: _c, updatedAt: _u, __v: _v, key: _k, ...rest } = body
    const current: any = await Settings.findOne({ key: 'global' }).lean()
    unmaskSettings(rest, current || {})
    const settings = await Settings.findOneAndUpdate(
      { key: 'global' },
      { key: 'global', ...rest },
      { upsert: true, new: true }
    ).lean()
    invalidateSettingsCache()
    return NextResponse.json({ success: true, settings: maskSettings(settings) })
  } catch {
    // No file fallback any more: re-reading the body here used to write `{}`
    // over data/settings.json.
    return NextResponse.json({ error: 'Failed to save settings' }, { status: 500 })
  }
}
