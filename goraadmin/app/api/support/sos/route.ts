import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'
import { guardAdmin } from '@/lib/admin-guard'

export async function GET(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const contacts = await SOSContact.find({ isActive: true }).sort({ createdAt: 1 }).lean()
    return NextResponse.json({ contacts })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const body = await req.json()
    const contact = await SOSContact.create(body)
    return NextResponse.json(contact, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
