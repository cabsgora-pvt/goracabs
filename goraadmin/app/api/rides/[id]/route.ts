import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'

export async function GET(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const ride = await Ride.findById(params.id).lean()
    if (!ride) return NextResponse.json({ error: 'Ride not found' }, { status: 404 })
    return NextResponse.json(ride)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
