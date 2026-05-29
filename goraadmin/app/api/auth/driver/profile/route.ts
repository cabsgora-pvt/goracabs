export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function GET(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    await connectDB()
    const driver = await Driver.findById(payload.id).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)

    return withCors({ driver })
  } catch (error: any) {
    return withCors({ error: error.message || 'Server error' }, 500)
  }
}
