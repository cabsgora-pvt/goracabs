export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import DocumentType from '@/models/DocumentType'
import { requireAdmin } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'
import { ensureDocTypes, docTypeKey, docTypeFields, publicDocType, appliesTo } from '@/lib/doc-types'

export async function OPTIONS() { return corsOptions() }

// GET                    → { documents } active ones, in order (driver app, public).
// GET ?vehicleType=Cab   → only those asked of a driver with that vehicle type.
// GET ?all=1             → every one, for the admin.
// POST (admin)           { name, category?, description?, needsNumber?, numberLabel?,
//                          frontLabel?, backLabel?, needsBack?, needsExpiry?, required?,
//                          isActive?, vehicleTypes?, order? }
export async function GET(req: NextRequest) {
  await connectDB()
  await ensureDocTypes()
  const all = req.nextUrl.searchParams.get('all') === '1' && !!requireAdmin(req)
  const vehicleType = req.nextUrl.searchParams.get('vehicleType')
  let rows: any[] = await DocumentType.find(all ? {} : { isActive: true }).sort({ order: 1, createdAt: 1 }).lean()
  if (!all && vehicleType) rows = rows.filter(d => appliesTo(d, vehicleType))
  return withCors({ documents: rows.map(publicDocType) })
}

export async function POST(req: NextRequest) {
  if (!requireAdmin(req)) return withCors({ error: 'Unauthorized' }, 401)
  try {
    const b = await req.json().catch(() => ({}))
    const f = docTypeFields(b)
    if (!f.name) return withCors({ error: 'Name is required' }, 400)
    await connectDB()
    await ensureDocTypes()
    let key = docTypeKey(b.key || f.name)
    if (!key) return withCors({ error: 'Name needs letters or numbers' }, 400)
    if (await DocumentType.exists({ key })) key = `${key}_${Date.now().toString(36).slice(-4)}`
    const max: any = await DocumentType.findOne().sort({ order: -1 }).select('order').lean()
    const d = await DocumentType.create({
      key,
      numberLabel: `${f.name} Number`,
      required: true, isActive: true,
      order: (max?.order || 0) + 1,
      ...f,
    })
    return withCors({ success: true, document: publicDocType(d.toObject()) }, 201)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
