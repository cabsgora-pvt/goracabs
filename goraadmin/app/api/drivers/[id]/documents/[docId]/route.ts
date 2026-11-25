import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { cleanDriverDoc } from '@/lib/admin-account'

// PUT { status?, number?, expiryDate?, frontUrl?, backUrl?, name? }
// The admin can verify / reject a driver's document or correct any part of it
// (number, expiry, replace a photo). Only the fields sent change.
export async function PUT(req: NextRequest, { params }: { params: { id: string; docId: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    await connectDB()
    const b = await req.json().catch(() => ({}))
    const clean = cleanDriverDoc(b)
    if ('error' in clean) return NextResponse.json({ error: clean.error }, { status: 400 })
    const driver = await Driver.findById(params.id)
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })

    const doc = driver.documents.id(params.docId)
    if (!doc) return NextResponse.json({ error: 'Document not found' }, { status: 404 })

    for (const [k, v] of Object.entries(clean.fields)) (doc as any)[k] = v
    if (clean.fields.frontUrl) doc.fileUrl = clean.fields.frontUrl
    await driver.save()
    return NextResponse.json({ success: true, driver: stripFace(driver.toObject()) })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

// DELETE → removes this document from the driver.
export async function DELETE(req: NextRequest, { params }: { params: { id: string; docId: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id) || !mongoose.isValidObjectId(params.docId)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
    await connectDB()
    const driver: any = await Driver.findByIdAndUpdate(params.id, { $pull: { documents: { _id: params.docId } } }, { new: true }).select('-faceSignature').lean()
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    return NextResponse.json({ success: true, driver })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

function stripFace(d: any) { delete d.faceSignature; return d }
