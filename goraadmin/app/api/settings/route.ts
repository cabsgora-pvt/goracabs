import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { getSettings } from '@/lib/settings'

export async function GET() {
  try {
    await connectDB()
    let settings = await Settings.findOne({ key: 'global' }).lean()
    if (!settings) {
      // Fallback to JSON file
      const fallback = getSettings()
      // Save to MongoDB for future use
      settings = await Settings.create({ key: 'global', ...fallback })
      settings = settings.toObject ? settings.toObject() : settings
    }
    return NextResponse.json(settings)
  } catch (error) {
    // Final fallback: read from JSON file directly
    try {
      const fallback = getSettings()
      return NextResponse.json(fallback)
    } catch {
      return NextResponse.json({ error: 'Failed to read settings' }, { status: 500 })
    }
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const settings = await Settings.findOneAndUpdate(
      { key: 'global' },
      { key: 'global', ...body },
      { upsert: true, new: true }
    ).lean()
    return NextResponse.json({ success: true, settings })
  } catch (error) {
    // Fallback: save to JSON file
    try {
      const body = await req.json().catch(() => ({}))
      const { saveSettings } = await import('@/lib/settings')
      saveSettings(body)
      return NextResponse.json({ success: true })
    } catch {
      return NextResponse.json({ error: 'Failed to save settings' }, { status: 500 })
    }
  }
}
