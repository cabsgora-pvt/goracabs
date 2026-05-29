import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Banner from '@/models/Banner'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const banner = await Banner.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!banner) return NextResponse.json({ error: 'Banner not found' }, { status: 404 })
    return NextResponse.json(banner)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await Banner.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
