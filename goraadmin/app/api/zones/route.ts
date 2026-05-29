import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'

export async function GET() {
  try {
    await connectDB()
    const zones = await Zone.find().sort({ createdAt: -1 }).lean()
    return NextResponse.json({ zones })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const zone = await Zone.create(body)
    return NextResponse.json(zone, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
