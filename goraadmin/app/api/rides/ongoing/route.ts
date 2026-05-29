export const dynamic = 'force-dynamic'
import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'

export async function GET() {
  try {
    await connectDB()
    const rides = await Ride.find({ status: { $in: ['accepted', 'arrived', 'ongoing'] } }).sort({ updatedAt: -1 }).lean()
    return NextResponse.json({ rides })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
