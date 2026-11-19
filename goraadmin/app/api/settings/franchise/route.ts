export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Settings from '@/models/Settings'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { isFranchiseMode, setFranchiseMode } from '@/lib/franchise'

// GET → { enabled, changedAt, changedBy }; PUT { enabled } — super admin only.
export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  await connectDB()
  const s: any = await Settings.findOne({ key: 'global' }).select('franchise').lean()
  return NextResponse.json({ enabled: await isFranchiseMode(), changedAt: s?.franchise?.changedAt || null, changedBy: s?.franchise?.changedBy || '' })
}

export async function PUT(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  const { enabled } = await req.json().catch(() => ({}))
  if (typeof enabled !== 'boolean') return NextResponse.json({ error: 'enabled must be true or false' }, { status: 400 })
  await setFranchiseMode(enabled, requireAdmin(req)?.email)
  return NextResponse.json({ enabled })
}
