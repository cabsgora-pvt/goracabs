import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const zone = await Zone.findById(params.id).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json(zone)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const zone = await Zone.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json(zone)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await Zone.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
