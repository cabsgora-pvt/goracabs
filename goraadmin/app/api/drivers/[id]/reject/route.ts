import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() {
  return corsOptions()
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json().catch(() => ({}))
    const driver = await Driver.findByIdAndUpdate(
      params.id,
      { status: 'rejected', rejectionReason: body.reason || '' },
      { new: true }
    ).lean()
    if (!driver) return withCors({ error: 'Driver not found' }, 404)
    return withCors({ success: true, driver })
  } catch (error: any) {
    return withCors({ error: error.message }, 500)
  }
}
