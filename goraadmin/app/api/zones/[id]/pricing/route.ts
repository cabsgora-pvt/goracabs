import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const zone = await Zone.findById(params.id).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ pricing: (zone as any).pricing || [] })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const zone = await Zone.findById(params.id)
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })

    const existingIdx = zone.pricing.findIndex(
      (p: any) => p.vehicleTypeName === body.vehicleTypeName && p.service === body.service
    )
    if (existingIdx >= 0) {
      zone.pricing[existingIdx] = { ...zone.pricing[existingIdx].toObject(), ...body }
    } else {
      zone.pricing.push(body)
    }
    await zone.save()
    return NextResponse.json({ pricing: zone.pricing })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { pricing } = await req.json()
    const zone = await Zone.findByIdAndUpdate(params.id, { pricing }, { new: true }).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ pricing: (zone as any).pricing })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
