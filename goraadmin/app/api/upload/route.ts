import { NextRequest } from 'next/server'
import { writeFile, mkdir } from 'fs/promises'
import path from 'path'
import crypto from 'crypto'
import { withCors, corsOptions } from '@/lib/cors'
import { requireDriverAuth, requireRider, requireAdmin } from '@/lib/auth'
import { validateUpload, MAX_UPLOAD_BYTES } from '@/lib/upload-validate'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    // Signed-in rider, driver or admin only.
    const actor = (requireDriverAuth(req) as any) || (requireRider(req) as any) || (requireAdmin(req) as any)
    if (!actor?.id) return withCors({ error: 'Unauthorized' }, 401)

    // Refuse oversized bodies before buffering them.
    const len = Number(req.headers.get('content-length') || 0)
    if (len && len > MAX_UPLOAD_BYTES + 64 * 1024) return withCors({ error: 'File too large (max 8 MB)' }, 413)

    let formData: FormData
    try { formData = await req.formData() } catch { return withCors({ error: 'No file provided' }, 400) }
    const file = formData.get('file')
    if (!file || typeof file === 'string') return withCors({ error: 'No file provided' }, 400)
    if (file.size > MAX_UPLOAD_BYTES) return withCors({ error: 'File too large (max 8 MB)' }, 413)

    const buffer = Buffer.from(await file.arrayBuffer())
    const v = validateUpload(file.name, file.size, buffer)
    if ('error' in v) return withCors({ error: v.error }, 400)

    // Extension from the detected content type, never the client's filename.
    const filename = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.${v.type.ext}`
    const dir = path.join(process.cwd(), 'public', 'uploads')
    await mkdir(dir, { recursive: true })
    await writeFile(path.join(dir, filename), buffer)

    return withCors({ url: `/uploads/${filename}` })
  } catch (e) {
    return withCors({ error: 'Upload failed' }, 500)
  }
}
