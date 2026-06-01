export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'

// GET all rental packages for a zone
export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const zone: any = await Zone.findById(params.id).select('rentalPackages').lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ packages: zone.rentalPackages || [] })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 500 })
  }
}

// PUT replace the full rental packages array (frontend sends edited list)
export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  try {
    await connectDB()
    const { packages } = await req.json()
    const zone: any = await Zone.findByIdAndUpdate(
      params.id,
      { rentalPackages: packages },
      { new: true }
    ).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ packages: zone.rentalPackages })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 400 })
  }
}
