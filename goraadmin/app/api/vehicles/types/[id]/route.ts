import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import VehicleType from '@/models/VehicleType'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const type = await VehicleType.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!type) return NextResponse.json({ error: 'Vehicle type not found' }, { status: 404 })
    return NextResponse.json(type)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await VehicleType.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
