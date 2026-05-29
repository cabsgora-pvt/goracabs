import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { getSettings } from '@/lib/settings'

export async function GET() {
  try {
    await connectDB()
    let settings = await Settings.findOne({ key: 'global' }).lean()
    if (!settings) {
      const fallback = getSettings()
      settings = fallback
    }
    return NextResponse.json((settings as any).payment || {})
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const settings = await Settings.findOneAndUpdate(
      { key: 'global' },
      { $set: { payment: body } },
      { upsert: true, new: true }
    ).lean()
    return NextResponse.json((settings as any).payment)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
