export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { requireDriverAuth } from '@/lib/auth'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// PATCH driver preferences (currently just acceptsOutstation; extend with more flags as features land)
export async function PATCH(req: NextRequest) {
  try {
    const payload = requireDriverAuth(req)
    if (!payload) return withCors({ error: 'Unauthorized' }, 401)

    const body = await req.json()
    const update: any = {}
    if (typeof body.acceptsOutstation === 'boolean') update.acceptsOutstation = body.acceptsOutstation

    await connectDB()
    const d = await Driver.findByIdAndUpdate(payload.id, update, { new: true }).select('acceptsOutstation').lean()
    return withCors({ success: true, preferences: { acceptsOutstation: (d as any)?.acceptsOutstation ?? false } })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
