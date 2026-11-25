import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import DocumentType from '@/models/DocumentType'
import { guardAdmin } from '@/lib/admin-guard'
import { cleanDriverDoc } from '@/lib/admin-account'

// POST { type (document key), number?, expiryDate?, frontUrl, backUrl?, status? }
// The admin adds a document to a driver (e.g. collected on paper or by
// WhatsApp). If the driver already has one of that type it is replaced.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    await connectDB()
    const b = await req.json().catch(() => ({}))
    const t: any = await DocumentType.findOne({ key: String(b.type || '') }).lean()
    if (!t) return NextResponse.json({ error: 'Choose a document type' }, { status: 400 })
    const clean = cleanDriverDoc({ ...b, name: t.name })
    if ('error' in clean) return NextResponse.json({ error: clean.error }, { status: 400 })
    const f = clean.fields
    if (!f.frontUrl) return NextResponse.json({ error: 'Upload the document photo' }, { status: 400 })
    if (t.needsNumber !== false && !f.number) return NextResponse.json({ error: `Enter the ${t.numberLabel || 'document number'}` }, { status: 400 })
    const driver = await Driver.findById(params.id)
    if (!driver) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    driver.documents = (driver.documents || []).filter((d: any) => d.type !== t.key)
    driver.documents.push({
      name: t.name, type: t.key, number: f.number || '', fileUrl: f.frontUrl, frontUrl: f.frontUrl,
      backUrl: f.backUrl || '', expiryDate: f.expiryDate || '', status: f.status || 'verified', uploadedAt: new Date(),
    })
    await driver.save()
    const out: any = driver.toObject(); delete out.faceSignature
    return NextResponse.json({ success: true, driver: out }, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
