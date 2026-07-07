export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const { documents } = await req.json()
    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return withCors({ error: 'Documents are required' }, 400)
    }

    await connectDB()
    const docs = documents.map((doc: {
      name: string; type?: string; number?: string;
      fileUrl?: string; frontUrl?: string; backUrl?: string; expiryDate?: string;
    }) => ({
      name: doc.name,
      type: doc.type,
      number: doc.number,
      fileUrl: doc.frontUrl || doc.fileUrl,
      frontUrl: doc.frontUrl || doc.fileUrl,
      backUrl: doc.backUrl,
      expiryDate: doc.expiryDate,
      status: 'pending',
      uploadedAt: new Date(),
    }))

    const driver = await Driver.findByIdAndUpdate(
      payload.id,
      { documents: docs, registrationStep: 'bank' },
      { new: true }
    ).lean()

    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
