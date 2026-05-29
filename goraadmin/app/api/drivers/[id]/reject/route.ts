import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json().catch(() => ({}))
    const driver = await Driver.findByIdAndUpdate(
      params.id,
      { status: 'rejected', rejectionReason: body.reason || '' },
      { new: true }
    ).lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    return NextResponse.json({ success: true, driver })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
