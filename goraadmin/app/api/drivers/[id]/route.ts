import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import Ride from '@/models/Ride'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const driver = await Driver.findById(params.id).lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    const recentRides = await Ride.find({ driverId: params.id }).sort({ createdAt: -1 }).limit(10).lean()
    return NextResponse.json({ driver, recentRides })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const driver = await Driver.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    return NextResponse.json(driver)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await Driver.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
