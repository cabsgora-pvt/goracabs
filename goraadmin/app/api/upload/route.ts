import { NextRequest } from 'next/server'
import { writeFile, mkdir } from 'fs/promises'
import path from 'path'
import crypto from 'crypto'
import { withCors, corsOptions } from '@/lib/cors'
import { requireActiveDriver, requireActiveRider, requireActiveAdmin, requireDriverAuth, requireRider } from '@/lib/auth'
import { validateUpload, MAX_UPLOAD_BYTES } from '@/lib/upload-validate'
import { limitHit } from '@/lib/rate-limit'
import { stripJpegGps } from '@/lib/exif-strip'
import { PUBLIC_DIR, PRIVATE_DIR, PRIVATE_PREFIX } from '@/lib/private-files'
import { connectDB } from '@/lib/mongodb'
import Upload from '@/models/Upload'

export async function OPTIONS() { return corsOptions() }

// Per actor: UPLOADS_PER_HOUR files and DAILY_QUOTA_BYTES over the last 24 h
// (admins: a larger hourly allowance, no byte quota).
const UPLOADS_PER_HOUR = 30
const ADMIN_UPLOADS_PER_HOUR = 200
const DAILY_QUOTA_BYTES = 100 * 1024 * 1024
const PURPOSES = new Set(['kyc', 'document', 'face', 'delivery_proof', 'profile', 'vehicle', 'banner', 'other'])

/**
 * POST multipart { file, private?, purpose? }   (also ?private=1&purpose=kyc)
 *   private=1 → stored outside public/, URL /api/files/<name> (owner / admins /
 *               zone admin / delivery-proof ride participants only).
 *   otherwise → public /uploads/<name> as before (profile, vehicle, banners).
 * JPEG GPS tags are removed before storing.
 */
export async function POST(req: NextRequest) {
  try {
    // Signed-in rider, driver or admin whose account is still active.
    let kind: 'driver' | 'rider' | 'admin' | null = null
    let ownerId = ''
    if (requireDriverAuth(req)) {
      const a = await requireActiveDriver(req)
      if (!a.ok) return withCors({ error: a.error, code: a.code }, a.status)
      kind = 'driver'; ownerId = a.id
    } else if (requireRider(req)) {
      const a = await requireActiveRider(req)
      if (!a.ok) return withCors({ error: a.error, code: a.code }, a.status)
      kind = 'rider'; ownerId = a.id
    } else {
      const adm = await requireActiveAdmin(req)
      if (adm?.id) { kind = 'admin'; ownerId = String(adm.id) }
    }
    if (!kind) return withCors({ error: 'Unauthorized' }, 401)

    // Refuse oversized bodies before buffering them.
    const len = Number(req.headers.get('content-length') || 0)
    if (len && len > MAX_UPLOAD_BYTES + 64 * 1024) return withCors({ error: 'File too large (max 8 MB)' }, 413)

    const perHour = kind === 'admin' ? ADMIN_UPLOADS_PER_HOUR : UPLOADS_PER_HOUR
    if (!(await limitHit(`upload:${kind}:${ownerId}`, perHour, 3600_000))) {
      return withCors({ error: 'Too many uploads. Please try again in a while.', code: 'UPLOAD_RATE_LIMIT' }, 429)
    }

    let formData: FormData
    try { formData = await req.formData() } catch { return withCors({ error: 'No file provided' }, 400) }
    const file = formData.get('file')
    if (!file || typeof file === 'string') return withCors({ error: 'No file provided' }, 400)
    if (file.size > MAX_UPLOAD_BYTES) return withCors({ error: 'File too large (max 8 MB)' }, 413)

    const sp = req.nextUrl.searchParams
    const flag = String(sp.get('private') ?? formData.get('private') ?? '').toLowerCase()
    const isPrivate = flag === '1' || flag === 'true'
    const purposeRaw = String(sp.get('purpose') ?? formData.get('purpose') ?? '').toLowerCase()
    const purpose = PURPOSES.has(purposeRaw) ? purposeRaw : undefined

    await connectDB()
    if (kind !== 'admin') {
      const since = new Date(Date.now() - 86_400_000)
      const agg = await Upload.aggregate([
        { $match: { ownerType: kind, ownerId, createdAt: { $gte: since } } },
        { $group: { _id: null, total: { $sum: '$size' } } },
      ])
      const used = Number(agg[0]?.total || 0)
      if (used + file.size > DAILY_QUOTA_BYTES) {
        return withCors({ error: 'Daily upload limit reached. Please try again tomorrow.', code: 'UPLOAD_QUOTA' }, 429)
      }
    }

    let buffer: Buffer = Buffer.from(await file.arrayBuffer())
    const v = validateUpload(file.name, file.size, buffer)
    if ('error' in v) return withCors({ error: v.error }, 400)
    let gpsStripped = false
    if (v.type.ext === 'jpg') {
      const s = stripJpegGps(buffer)
      buffer = s.buf; gpsStripped = s.stripped
    }

    // Extension from the detected content type, never the client's filename.
    const filename = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.${v.type.ext}`
    const dir = isPrivate ? PRIVATE_DIR() : PUBLIC_DIR()
    await mkdir(dir, { recursive: true })
    await writeFile(path.join(dir, filename), buffer)
    await Upload.create({ name: filename, ownerType: kind, ownerId, private: isPrivate, purpose, mime: v.type.mime, size: buffer.length, gpsStripped })

    const url = isPrivate ? `${PRIVATE_PREFIX}${filename}` : `/uploads/${filename}`
    return withCors({ url, private: isPrivate })
  } catch (e) {
    return withCors({ error: 'Upload failed' }, 500)
  }
}
