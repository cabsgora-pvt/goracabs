import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import PromoCode from '@/models/PromoCode'

export async function GET() {
  try {
    await connectDB()
    const promos = await PromoCode.find().sort({ createdAt: -1 }).lean()
    return NextResponse.json({ promos })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const promo = await PromoCode.create(body)
    return NextResponse.json(promo, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
