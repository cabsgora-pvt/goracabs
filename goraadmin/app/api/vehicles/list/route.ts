import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'

export async function GET() {
  try {
    await connectDB()
    const vehicles = await Driver.find(
      { vehicleNumber: { $exists: true, $ne: '' } },
      { name: 1, vehicleNumber: 1, vehicleModel: 1, vehicleType: 1, status: 1, createdAt: 1 }
    ).sort({ createdAt: -1 }).lean()
    return NextResponse.json({ vehicles })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
