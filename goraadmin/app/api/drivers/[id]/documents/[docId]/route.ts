import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'

export async function PUT(req: NextRequest, { params }: { params: { id: string; docId: string } }) {
  try {
    await connectDB()
    const { status } = await req.json()
    const driver = await Driver.findById(params.id)
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })

    const doc = driver.documents.id(params.docId)
    if (!doc) return NextResponse.json({ error: 'Document not found' }, { status: 404 })

    doc.status = status
    await driver.save()
    return NextResponse.json({ success: true, driver: driver.toObject() })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
