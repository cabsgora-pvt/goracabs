import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { withCors, corsOptions } from '@/lib/cors'
import AppConfig from '@/models/AppConfig'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'

// Only these top-level sections of the AppConfig document may be written. The
// dashboard posts the whole doc back (with _id / timestamps / __v) — anything
// outside this list is dropped rather than $set.
const WRITABLE_KEYS = ['banners', 'offers', 'coupons', 'places', 'faqs', 'whyChooseUs', 'support', 'referral', 'version'] as const
const APPS = ['user', 'driver']

export async function OPTIONS() { return corsOptions() }

// Force update: the apps compare their own version with `version` (public in
// GET): below minVersion — or forceUpdate with a newer latestVersion — they
// block with `message` and a button to storeUrl.
const VER_RE = /^\d{1,4}(\.\d{1,4}){0,3}$/
function cleanVersion(v: any): { version: any } | { error: string } {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return { error: 'Invalid version settings' }
  const latestVersion = String(v.latestVersion ?? '1.0.0').trim()
  const minVersion = String(v.minVersion ?? '1.0.0').trim()
  if (!VER_RE.test(latestVersion) || !VER_RE.test(minVersion)) return { error: 'Versions must look like 1.4.0' }
  const storeUrl = String(v.storeUrl ?? '').trim()
  if (storeUrl && !/^https:\/\/[^\s]+$/i.test(storeUrl)) return { error: 'Store link must start with https://' }
  return { version: { latestVersion, minVersion, forceUpdate: v.forceUpdate === true, message: String(v.message ?? '').slice(0, 300), storeUrl: storeUrl.slice(0, 300) } }
}

// GET /api/app-config?app=user  → returns the config (creates a default doc if none)
export async function GET(req: NextRequest) {
  try {
    await connectDB()
    const app = req.nextUrl.searchParams.get('app') || 'user'
    if (!APPS.includes(app)) return withCors({ error: 'Unknown app' }, 400)
    let cfg = await AppConfig.findOne({ app }).lean()
    if (!cfg) {
      cfg = (await AppConfig.create({ app })).toObject()
    }
    return withCors({ config: cfg })
  } catch (e: any) {
    return withCors({ error: e.message }, 500)
  }
}

// POST /api/app-config  body: { app, ...sections }  → upsert (admin + password)
export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const pwdDenied = await requireAdminPassword(req); if (pwdDenied) return pwdDenied
    await connectDB()
    let body: any
    try { body = await req.json() } catch { return withCors({ error: 'Invalid request' }, 400) }
    if (!body || typeof body !== 'object' || Array.isArray(body)) return withCors({ error: 'Invalid request' }, 400)
    const app = body.app || 'user'
    if (!APPS.includes(app)) return withCors({ error: 'Unknown app' }, 400)
    const set: Record<string, any> = {}
    for (const k of WRITABLE_KEYS) if (k in body) set[k] = body[k]
    if (!Object.keys(set).length) return withCors({ error: 'Nothing to update' }, 400)
    if ('version' in set) {
      const v = cleanVersion(set.version)
      if ('error' in v) return withCors({ error: v.error }, 400)
      set.version = v.version
    }
    const cfg = await AppConfig.findOneAndUpdate(
      { app },
      { $set: set },
      { new: true, upsert: true, setDefaultsOnInsert: true },
    ).lean()
    return withCors({ config: cfg })
  } catch (e: any) {
    return withCors({ error: e?.name === 'ValidationError' || e?.name === 'CastError' ? 'Invalid config' : 'Could not save config' }, 400)
  }
}
