import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import FleetOwner from '@/models/FleetOwner'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const owner = await FleetOwner.findById(params.id).lean()
    if (!owner) return NextResponse.json({ error: 'Fleet owner not found' }, { status: 404 })
    return NextResponse.json(owner)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const owner = await FleetOwner.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!owner) return NextResponse.json({ error: 'Fleet owner not found' }, { status: 404 })
    return NextResponse.json(owner)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await FleetOwner.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
