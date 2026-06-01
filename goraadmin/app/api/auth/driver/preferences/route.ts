export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// Both POST and PATCH supported so CORS allow-method differences don't matter
async function handle(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const body = await req.json()
    const update: any = {}
    if (typeof body.acceptsOutstation === 'boolean') update.acceptsOutstation = body.acceptsOutstation
    if (typeof body.acceptsRental === 'boolean') update.acceptsRental = body.acceptsRental
    if (typeof body.acceptsHireDriver === 'boolean') update.acceptsHireDriver = body.acceptsHireDriver

    await connectDB()
    const d = await Driver.findByIdAndUpdate(payload.id, update, { new: true }).select('acceptsOutstation acceptsRental acceptsHireDriver').lean()
    return withCors({ success: true, preferences: {
      acceptsOutstation: (d as any)?.acceptsOutstation ?? false,
      acceptsRental: (d as any)?.acceptsRental ?? false,
      acceptsHireDriver: (d as any)?.acceptsHireDriver ?? false,
    } })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

export const POST = handle
export const PATCH = handle
