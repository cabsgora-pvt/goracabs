import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SurgePrice from '@/models/SurgePrice'

export async function GET() {
  await connectDB()
  const surges = await SurgePrice.find().sort({ createdAt: -1 }).lean()
  return NextResponse.json({ surges })
}

export async function POST(req: NextRequest) {
  await connectDB()
  const body = await req.json()
  const surge = await SurgePrice.create(body)
  return NextResponse.json(surge, { status: 201 })
}
