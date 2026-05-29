import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import SOSContact from '@/models/SOSContact'

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const body = await req.json()
    const contact = await SOSContact.findByIdAndUpdate(params.id, body, { new: true }).lean()
    if (!contact) return NextResponse.json({ error: 'Contact not found' }, { status: 404 })
    return NextResponse.json(contact)
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}

export async function DELETE(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    await SOSContact.findByIdAndDelete(params.id)
    return NextResponse.json({ success: true })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
