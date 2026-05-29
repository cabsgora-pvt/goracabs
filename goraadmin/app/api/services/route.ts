import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import ServiceConfig from '@/models/ServiceConfig'

export async function GET() {
  try {
    await connectDB()
    const services = await ServiceConfig.find().lean()
    return NextResponse.json({ services })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const service = await ServiceConfig.findOneAndUpdate(
      { service: body.service },
      body,
      { upsert: true, new: true }
    ).lean()
    return NextResponse.json(service, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
