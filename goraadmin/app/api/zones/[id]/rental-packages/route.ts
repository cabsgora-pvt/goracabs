export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Zone from '@/models/Zone'
import { guardAdmin } from '@/lib/admin-guard'
import { RENTAL_FIELDS, keptAdminRef } from '@/lib/zone-features'

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
    const denied = guardAdmin(req); if (denied) return denied
    await connectDB()
    const { packages } = await req.json()
    // New fares reset the reference zone admin limits use; untouched ones keep it.
    const current: any = await Zone.findById(params.id).select('rentalPackages').lean()
    const byId = new Map<string, any>((current?.rentalPackages || []).map((p: any) => [String(p._id), p]))
    const rows = Array.isArray(packages)
      ? packages.map(({ adminRef: _r, ...p }: any) => ({ ...p, adminRef: keptAdminRef(byId.get(String(p._id)), p, RENTAL_FIELDS) }))
      : packages
    const zone: any = await Zone.findByIdAndUpdate(
      params.id,
      { rentalPackages: rows },
      { new: true }
    ).lean()
    if (!zone) return NextResponse.json({ error: 'Zone not found' }, { status: 404 })
    return NextResponse.json({ packages: zone.rentalPackages })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 400 })
  }
}
