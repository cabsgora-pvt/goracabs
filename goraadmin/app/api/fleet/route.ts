import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import FleetOwner from '@/models/FleetOwner'

export async function GET() {
  try {
    await connectDB()
    const fleet = await FleetOwner.find().sort({ createdAt: -1 }).lean()
    return NextResponse.json({ fleet })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const owner = await FleetOwner.create(body)
    return NextResponse.json(owner, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
