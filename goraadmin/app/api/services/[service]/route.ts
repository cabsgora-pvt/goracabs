import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import ServiceConfig from '@/models/ServiceConfig'

export async function GET(req: NextRequest, { params }: { params: { service: string } }) {
  try {
    await connectDB()
    const config = await ServiceConfig.findOne({ service: params.service }).lean()
    if (!config) return NextResponse.json({ error: 'Service not found' }, { status: 404 })
    return NextResponse.json(config)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { service: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const config = await ServiceConfig.findOneAndUpdate(
      { service: params.service },
      { ...body, service: params.service },
      { upsert: true, new: true }
    ).lean()
    return NextResponse.json(config)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
