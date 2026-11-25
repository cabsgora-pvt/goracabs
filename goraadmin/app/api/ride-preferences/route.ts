export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import RidePreference from '@/models/RidePreference'
import { requireAdmin } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { docTypeKey } from '@/lib/doc-types'
import { PREF_SERVICES } from '@/lib/ride-prefs'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { guardAdmin } from '@/lib/admin-guard'

export async function OPTIONS() { return corsOptions() }

// GET          → { preferences } active ones (both apps, public).
// GET ?all=1   → every one, for the admin.
// POST (admin) { name, description?, icon?, services?, order? }
export async function GET(req: NextRequest) {
  await connectDB()
  const all = req.nextUrl.searchParams.get('all') === '1' && !!requireAdmin(req)
  const rows: any[] = await RidePreference.find(all ? {} : { isActive: true }).sort({ order: 1, createdAt: 1 }).lean()
  return withCors({
    preferences: rows.map(p => ({
      id: String(p._id), key: p.key, name: p.name, description: p.description || '', icon: p.icon || 'star',
      services: p.services?.length ? p.services : PREF_SERVICES, isActive: p.isActive !== false, order: p.order || 0,
    })),
  })
}

export async function POST(req: NextRequest) {
  const denied = await guardAdmin(req); if (denied) return denied
  const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
  await auditAdminBody(req, requireAdmin(req), 'ride_preference.create', undefined)
  try {
    const b = await req.json().catch(() => ({}))
    const name = String(b.name || '').trim().slice(0, 40)
    if (!name) return withCors({ error: 'Name is required' }, 400)
    await connectDB()
    let key = docTypeKey(name)
    if (!key) return withCors({ error: 'Name needs letters or numbers' }, 400)
    if (await RidePreference.exists({ key })) key = `${key}_${Date.now().toString(36).slice(-4)}`
    const services = Array.isArray(b.services) ? b.services.filter((s: string) => PREF_SERVICES.includes(s)) : []
    const max: any = await RidePreference.findOne().sort({ order: -1 }).select('order').lean()
    const p = await RidePreference.create({
      key, name, description: String(b.description || '').slice(0, 120), icon: String(b.icon || 'star').slice(0, 30),
      services: services.length ? services : ['taxi', 'rental', 'outstation'], isActive: b.isActive !== false,
      order: (max?.order || 0) + 1,
    })
    return withCors({ success: true, preference: p.toObject() }, 201)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
