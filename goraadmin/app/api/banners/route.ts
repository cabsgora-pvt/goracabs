import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Banner from '@/models/Banner'

export async function GET() {
  try {
    await connectDB()
    const banners = await Banner.find().sort({ sortOrder: 1, createdAt: -1 }).lean()
    return NextResponse.json({ banners })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const banner = await Banner.create(body)
    return NextResponse.json(banner, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
