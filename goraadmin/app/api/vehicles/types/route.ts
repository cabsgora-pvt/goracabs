import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import VehicleType from '@/models/VehicleType'

export async function GET() {
  try {
    await connectDB()
    const types = await VehicleType.find().sort({ sortOrder: 1, createdAt: 1 }).lean()
    return NextResponse.json({ types })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const type = await VehicleType.create(body)
    return NextResponse.json(type, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
