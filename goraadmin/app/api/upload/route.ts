import { NextRequest } from 'next/server'
import { writeFile } from 'fs/promises'
import path from 'path'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData()
    const file = formData.get('file') as File
    if (!file) return withCors({ error: 'No file provided' }, 400)

    const bytes = await file.arrayBuffer()
    const buffer = Buffer.from(bytes)

    const ext = file.name.split('.').pop() || 'jpg'
    const filename = `${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`
    const uploadPath = path.join(process.cwd(), 'public', 'uploads', filename)

    await writeFile(uploadPath, buffer)

    return withCors({ url: `/uploads/${filename}` })
  } catch (e) {
    return withCors({ error: 'Upload failed' }, 500)
  }
}
