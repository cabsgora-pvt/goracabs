import { NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'

export async function GET() {
  try {
    await connectDB()
    const drivers = await Driver.find({ status: 'pending' }).sort({ createdAt: -1 }).lean()
    return NextResponse.json({ drivers })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
