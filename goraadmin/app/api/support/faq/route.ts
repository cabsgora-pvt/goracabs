import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import FAQ from '@/models/FAQ'

export async function GET() {
  try {
    await connectDB()
    const faqs = await FAQ.find({ isActive: true }).sort({ sortOrder: 1, createdAt: 1 }).lean()
    return NextResponse.json({ faqs })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    await connectDB()
    const body = await req.json()
    const faq = await FAQ.create(body)
    return NextResponse.json(faq, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
